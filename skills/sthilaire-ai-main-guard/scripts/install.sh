#!/bin/bash
# sthilaire-ai-main-guard: installs the GIT layer into the current repo.
# The Claude layer is the plugin's own hook; nothing Claude-side is copied here.
#   install.sh [BRANCH]           install or update (branch: arg > existing file > main)
#   install.sh --migrate [BRANCH] same, plus remove an old per-repo Claude hook (known versions only)
#   install.sh --check            self-test installer + plugin hook in a throwaway repo
set -euo pipefail

NAME=sthilaire-ai-main-guard
URL=https://github.com/sthilaire/protecting-main-branch#readme
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$HERE/../../../hooks/block-main-git.sh"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# known FILE: written by this tool, by the claude-config skill, or by the old
# setup-branch-protection.sh (fingerprint taken with the branch name blanked out).
V1=" 7bb4c8baf90c77d2 0c7c065255012582 0e7ab1436531fdc2 "
known() {
  grep -qE "$NAME|branch-protection skill" "$1" && return 0
  local h
  h=$(sed -E 's/protected_branch="[^"]*"/protected_branch="X"/; s/== "[^"]*" \]\]/== "X" ]]/; s/to [^ ]+ is blocked/to X is blocked/' "$1" | sha256sum | cut -c1-16)
  [[ "$V1" == *" $h "* ]]
}

check() {
  local T fail=0
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  t() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
  hook() { jq -nc --arg c "$1" --arg d "$2" '{cwd:$d, tool_input:{command:$c}}' | bash "$HOOK"; }
  mkdir "$T/repo" "$T/out"; cd "$T/repo"
  git init -q -b main; git config user.email t@t; git config user.name t; git config commit.gpgsign false
  t "plugin hook ignores a repo without protected-branch" '[[ -z $(hook "git commit -m x" "$T/repo") ]]'
  printf '# test\n' > CLAUDE.md
  bash "$HERE/install.sh" >/dev/null && bash "$HERE/install.sh" >/dev/null
  t "install is idempotent (one CLAUDE.md pointer)"  '[[ $(grep -c "$NAME:start" CLAUDE.md) == 1 ]]'
  t "core.hooksPath = .githooks"                     '[[ $(git config core.hooksPath) == .githooks ]]'
  t "plugin hook denies git commit on main"          '[[ $(hook "git commit -m x" "$T/repo") == *deny* ]]'
  t "plugin hook denies git push on main"            '[[ $(hook "git status && git push" "$T/repo") == *deny* ]]'
  t "plugin hook allows git status on main"          '[[ -z $(hook "git status" "$T/repo") ]]'
  t "git commit blocked on main"                     '! git commit -q --allow-empty -m x 2>/dev/null'
  t "pre-push blocks refs/heads/main"                '! echo "f a refs/heads/main b" | .githooks/pre-push origin url 2>/dev/null'
  t "pre-push allows a feature ref"                  'echo "f a refs/heads/feat/x b" | .githooks/pre-push origin url'
  git checkout -q -b feat/x
  t "git commit allowed off main"                    'git commit -q --allow-empty -m x'
  t "plugin hook allows commit off main"             '[[ -z $(hook "git commit -m x" "$T/repo") ]]'
  t "plugin hook allows outside a repo"              '[[ -z $(hook "git commit -m x" "$T/out") ]]'
  exit $fail
}

MIGRATE=0; B=""
case "${1:-}" in
  --check) check ;;
  --migrate) MIGRATE=1; B=${2:-} ;;
  *) B=${1:-} ;;
esac

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT"

# Branch: argument > existing protected-branch file > old hard-coded hook > main.
[ -z "$B" ] && [ -f .githooks/protected-branch ] && B=$(tr -d '[:space:]' < .githooks/protected-branch)
[ -z "$B" ] && [ -f .githooks/pre-commit ] && B=$(sed -n 's/^protected_branch="\(.*\)"$/\1/p' .githooks/pre-commit)
B=${B:-main}
git check-ref-format --branch "$B" >/dev/null || { echo "bad branch name: $B" >&2; exit 1; }

# Refuse before writing anything if a hook exists that we don't recognise.
for f in .githooks/pre-commit .githooks/pre-push; do
  if [ -e "$f" ] && ! known "$f"; then echo "ABORT: $f exists and is not ours; merge by hand" >&2; exit 1; fi
done

mkdir -p .githooks
put() {  # put FILE: write stdin to FILE, report whether it changed
  local new; new=$(cat)
  if [ -e "$1" ] && [ "$new" = "$(cat "$1")" ]; then echo "unchanged $1"
  else printf '%s\n' "$new" > "$1"; echo "wrote $1"; fi
}

echo "$B" | put .githooks/protected-branch

put .githooks/pre-commit <<EOF
#!/bin/bash
# $NAME: blocks \`git commit\` on the protected branch.
# Branch name: .githooks/protected-branch (absent = main). $URL
root=\$(git rev-parse --show-toplevel)
protected=\$(cat "\$root/.githooks/protected-branch" 2>/dev/null | tr -d '[:space:]'); protected=\${protected:-main}
if [ "\$(git symbolic-ref --short HEAD 2>/dev/null)" = "\$protected" ]; then
  echo "Commit to '\$protected' rejected. Branch off first (e.g. git checkout -b feat/<slug>)." >&2
  exit 1
fi
exit 0
EOF

put .githooks/pre-push <<EOF
#!/bin/bash
# $NAME: blocks \`git push\` whose destination is the protected branch.
# Branch name: .githooks/protected-branch (absent = main). $URL
root=\$(git rev-parse --show-toplevel)
protected=\$(cat "\$root/.githooks/protected-branch" 2>/dev/null | tr -d '[:space:]'); protected=\${protected:-main}
while read -r local_ref local_sha remote_ref remote_sha; do
  if [ "\$remote_ref" = "refs/heads/\$protected" ]; then
    echo "Push to '\$protected' rejected. Branch off and open an MR/PR instead (e.g. git checkout -b feat/<slug>)." >&2
    exit 1
  fi
done
exit 0
EOF
chmod +x .githooks/pre-commit .githooks/pre-push

git config core.hooksPath .githooks; echo "set core.hooksPath=.githooks"

# Old per-repo Claude hook: the plugin replaces it. Remove only known versions.
H=.claude/hooks/block-main-git.sh; S=.claude/settings.json
if [ -e "$H" ] && [ "$MIGRATE" = 0 ]; then
  echo "NOTE: old per-repo Claude hook $H found; with the plugin it denies twice. Run install.sh --migrate."
elif [ -e "$H" ]; then
  if known "$H"; then
    rm "$H"; echo "removed $H"
    rmdir .claude/hooks 2>/dev/null && echo "removed empty .claude/hooks" || true
    if [ -f "$S" ]; then
      jq 'if .hooks.PreToolUse then
            .hooks.PreToolUse |= (map(.hooks |= map(select((.command // "") | contains("block-main-git.sh") | not)))
                                  | map(select(.hooks | length > 0)))
            | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
            | if .hooks == {} then del(.hooks) else . end
          else . end' "$S" > "$S.tmp"
      if cmp -s "$S" "$S.tmp"; then rm "$S.tmp"; echo "unchanged $S (no hook entry)"
      else mv "$S.tmp" "$S"; echo "removed hook entry from $S"; fi
      [ "$(jq -c . "$S")" = "{}" ] && echo "NOTE: $S is now {}; delete it if nothing else needs it"
    fi
  else
    echo "MANUAL: $H was changed locally; compare it with the plugin hook, then delete it and its $S entry by hand"
  fi
elif [ "$MIGRATE" = 1 ]; then
  echo "no per-repo Claude hook to migrate"
fi

# CLAUDE.md: one-line pointer between markers. Replaces our block, the old
# branch-protection block, or the old appended sections. Skipped if no CLAUDE.md.
if [ -f CLAUDE.md ]; then
  export BLK="<!-- $NAME:start -->
\`$B\` is protected by the [$NAME]($URL) plugin: never commit or push to it. Branch first (\`feat/<slug>\`) and open an MR/PR.
<!-- $NAME:end -->"
  replace() {  # replace START_RE END_RE (empty END_RE = old sections, end at next unrelated heading)
    awk -v s="$1" -v e="$2" '
      !done && $0 ~ s { print ENVIRON["BLK"]; skip=1; done=1; next }
      skip && e != "" && $0 ~ e { skip=0; next }
      skip && e == "" && /^## / && $0 !~ /^## Main branch protection/ { skip=0; print "" }
      !skip' CLAUDE.md > CLAUDE.md.tmp
    if cmp -s CLAUDE.md CLAUDE.md.tmp; then rm CLAUDE.md.tmp; echo "unchanged CLAUDE.md"
    else mv CLAUDE.md.tmp CLAUDE.md; echo "$3"; fi
  }
  if grep -q "$NAME:start" CLAUDE.md; then
    replace "$NAME:start" "$NAME:end" "updated CLAUDE.md pointer"
  elif grep -q 'branch-protection:start' CLAUDE.md; then
    replace 'branch-protection:start' 'branch-protection:end' "replaced old branch-protection block in CLAUDE.md with pointer"
  elif grep -qF '## Main branch protection (Claude Code hook)' CLAUDE.md; then
    replace '^## Main branch protection \\(Claude Code hook\\)' '' "replaced old 'Main branch protection' sections in CLAUDE.md with pointer"
  elif grep -qi '^## Branch strategy' CLAUDE.md; then
    echo "MANUAL: CLAUDE.md has its own 'Branch strategy' section; merge by hand and wrap the pointer in <!-- $NAME:start/end -->"
  else
    { echo; echo "$BLK"; } >> CLAUDE.md; echo "appended CLAUDE.md pointer"
  fi
else
  echo "SKIPPED: no CLAUDE.md"
fi

echo
echo "Done. Commit .githooks/ (and CLAUDE.md). Other clones: git config core.hooksPath .githooks"
echo "The Claude layer comes from the $NAME plugin. --no-verify bypasses git hooks."
