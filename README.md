# sthilaire-ai-main-guard

Source: https://github.com/sthilaire/protecting-main-branch

## Why this exists

An AI agent in your terminal uses your git credentials. It will commit and push
to `main` as readily as you would — faster, and without the pause where you
think "wait, wrong branch." This is my process for keeping `main` reviewable in
that world: the agent works on a branch, and everything reaches `main` through
an MR/PR. It's opinionated on purpose. Background:

- [Claude Code main branch protection](https://wphilltech.com/claude-code-main-branch-protection/)
- [Git hooks for branch protection](https://wphilltech.com/git-hooks-branch-protection/)

## Two layers

1. **Claude layer — a Claude Code plugin hook.** Denies `git commit` / `git push`
   run through Claude's Bash tool while the repo is on its protected branch.
   It runs from the plugin, so there's one copy on your machine, not one per repo.
2. **Git layer — `pre-commit` + `pre-push` hooks in each repo.** Blocks the same
   for every git client: terminal, editor, CI. Git can't read plugin files, so
   this layer lives in the repo.

Both read the branch name from `.githooks/protected-branch` (one line,
committed). The plugin hook acts **only in repos that have that file** — it
won't touch scratch repos or other people's clones.

## Install

**1. The plugin** (once per machine), inside Claude Code:

```
/plugin marketplace add sthilaire/protecting-main-branch
/plugin install sthilaire-ai-main-guard@sthilaire-ai-main-guard
```

On Claude Code 2.1.275+ that's one step:
`/plugin install sthilaire-ai-main-guard --marketplace sthilaire/protecting-main-branch`

Then restart Claude Code — hooks load at session start.

**2. The git layer** (once per repo). Ask Claude to "protect main" and the
plugin's skill runs the installer, or run it yourself from inside the repo:

```bash
git clone https://github.com/sthilaire/protecting-main-branch.git /tmp/protecting-main-branch
bash /tmp/protecting-main-branch/skills/sthilaire-ai-main-guard/scripts/install.sh          # main
bash /tmp/protecting-main-branch/skills/sthilaire-ai-main-guard/scripts/install.sh trunk    # another branch
```

It writes:

```
.githooks/protected-branch   # the branch name (this is also the plugin's opt-in)
.githooks/pre-commit         # rejects a commit while on the protected branch
.githooks/pre-push           # rejects a push targeting the protected branch
CLAUDE.md                    # one-line pointer between markers (only if CLAUDE.md exists)
```

and runs `git config core.hooksPath .githooks`. Re-running is safe. It stops
with `ABORT` rather than overwrite a hook it didn't write, and prints `MANUAL`
when something needs a human.

`install.sh --check` self-tests the installer and the plugin hook in a
throwaway repo.

### Upgrading from the old per-repo setup

Earlier versions copied a Claude hook into each project
(`.claude/hooks/block-main-git.sh`). With the plugin installed, that copy makes
every block fire twice. From inside each such project:

```bash
bash /tmp/protecting-main-branch/skills/sthilaire-ai-main-guard/scripts/install.sh --migrate
```

It removes the old hook and its `.claude/settings.json` entry (other settings
are kept), rewrites the git hooks to read the branch at runtime, and shrinks
the old CLAUDE.md sections to the pointer. It only removes files that match a
version this repo generated; a locally edited hook is reported as `MANUAL`.

`scripts/setup-branch-protection.sh` still works, but is deprecated: it prints
the plugin instructions, then runs the installer above.

## The one manual step

`core.hooksPath` is git config, not a tracked file — git deliberately doesn't
let a repo silently enable hooks for everyone who clones it. Every **other**
clone (a teammate, a CI runner, a fresh checkout) needs, once:

```bash
git config core.hooksPath .githooks
```

## Limitations

- **The Claude layer only covers Claude Code's Bash tool.** A plain terminal
  `git push` isn't touched by it, and neither are other AI tools.
- **`--no-verify` bypasses both git hooks by design.** Git hooks are a local
  convention, not a security boundary. For guarantees regardless of local
  setup, use server-side branch protection on GitHub/GitLab.
- **Hooks load at session start.** After installing or updating the plugin,
  restart Claude Code.
- **The plugin hook matches `git commit` / `git push` at the start of a
  command.** Forms like `git -C dir commit` slip past it; the git hooks still
  catch them.
- Fast-forward merges and `git reset --hard` skip `pre-commit` (no new commit
  object), but `pre-push` still catches them before anything leaves the machine.

## License

MIT — see [LICENSE](LICENSE).
