---
name: sthilaire-ai-main-guard
description: Use when asked to protect main (or another branch) from direct commits and pushes in a git repo, to install or update the git hooks for the sthilaire-ai-main-guard plugin, or to migrate a repo off an old per-repo block-main-git.sh Claude hook.
---

# sthilaire-ai-main-guard

Two layers, one source of truth.

- **Claude layer:** this plugin's own PreToolUse hook. Nothing is copied into the project. It acts only in repos that have `.githooks/protected-branch`.
- **Git layer:** `.githooks/pre-commit` and `pre-push`, per repo. Covers every git client.
- **Source of truth:** `.githooks/protected-branch` (one line, committed). Both layers read it.

All logic is in `scripts/install.sh` next to this file. Do not re-implement it by hand, and never edit the installed hooks in a project: change them here, at the source.

## Steps

1. **Confirm** the repo (`git rev-parse --show-toplevel`) and the branch name (default `main`).
2. **CLAUDE.md:** if the repo has none, ask once whether to create it. Never create README, CONTRIBUTING or LICENSE.
3. **Install** from the repo root: `bash <this-skill-dir>/scripts/install.sh [BRANCH]`
   - Repo has an old `.claude/hooks/block-main-git.sh`? Use `--migrate [BRANCH]` instead.
4. **Verify:** `bash <this-skill-dir>/scripts/install.sh --check` (throwaway repo; exit 0 = good).
5. **Tell the user:**
   - Commit `.githooks/` and CLAUDE.md. Other clones run `git config core.hooksPath .githooks` once.
   - `--no-verify` bypasses git hooks. A guardrail, not security; use server-side branch rules for a guarantee.

## What the script reports

- `ABORT:` a git hook exists that this tool did not write. Merge by hand.
- `MANUAL:` CLAUDE.md has its own "Branch strategy" section, or the old Claude hook was edited locally. Resolve by hand.
- `NOTE:` an old per-repo Claude hook is present; rerun with `--migrate`.
