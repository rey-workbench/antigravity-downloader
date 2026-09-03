#!/usr/bin/env bash
# Antigravity Linux Status Inspector
# Shows installed helper-managed apps, versions, and binaries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  # shellcheck source=lib/common.sh
  source "$SCRIPT_DIR/lib/common.sh"
else
  BASE_URL="${ANTIGRAVITY_LINUX_BASE_URL:-${ANTIGRAVITY_LINUX_INSTALLER_URL%/*}}"
  [ -n "$BASE_URL" ] || BASE_URL="https://rey-workbench.github.io/antigravity-downloader"
  source <(curl -fsSL "$BASE_URL/lib/common.sh")
fi

show_status
