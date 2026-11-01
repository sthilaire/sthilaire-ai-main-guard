#!/bin/bash
# DEPRECATED. This script used to copy a Claude Code hook into each project.
# The Claude layer is now the sthilaire-ai-main-guard plugin, so it runs from one
# place. This wrapper installs the git layer and tells you how to get the plugin.
cat >&2 <<'MSG'
NOTICE: setup-branch-protection.sh is deprecated.
  Claude layer -> install the plugin once, inside Claude Code:
    /plugin marketplace add sthilaire/sthilaire-ai-main-guard
    /plugin install sthilaire-ai-main-guard@sthilaire-ai-main-guard
  Git layer    -> installing it now via skills/sthilaire-ai-main-guard/scripts/install.sh
  Upgrading an old install? Run that script with --migrate.
  https://github.com/sthilaire/sthilaire-ai-main-guard#readme

MSG
exec bash "$(dirname "${BASH_SOURCE[0]}")/../skills/sthilaire-ai-main-guard/scripts/install.sh" "$@"
