#!/bin/bash
# sthilaire-ai-main-guard: Claude Code PreToolUse hook (Bash tool).
# Denies `git commit` / `git push` while the repo is on its protected branch.
# Acts only in opted-in repos: those with .githooks/protected-branch (one line,
# the branch name). Your own terminal is untouched.
in=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
# ponytail: matches `git commit|push` at a command start; misses `git -C dir commit`. Extend the regex if that bites.
grep -qE '(^|[;&|(])\s*git\s+(commit|push)\b' <<<"$cmd" || exit 0
dir=$(jq -r '.cwd // empty' <<<"$in"); dir=${dir:-$PWD}
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
f="$root/.githooks/protected-branch"
[ -f "$f" ] || exit 0
protected=$(tr -d '[:space:]' < "$f"); protected=${protected:-main}
[ "$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null)" = "$protected" ] || exit 0
jq -n --arg b "$protected" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny",
  permissionDecisionReason: "Blocked by sthilaire-ai-main-guard: git commit/push on \($b). Create or checkout a feature branch first (e.g. `git checkout -b feat/<slug>`), then retry."}}'
exit 0
