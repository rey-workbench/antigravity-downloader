#!/usr/bin/env bash
# Antigravity Linux Uninstaller
# Removes helper-managed Google Antigravity desktop and IDE installations.
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

usage() {
  cat <<'USAGE'
Antigravity Linux Uninstaller

Usage:
  uninstall.sh [options]

Options:
  -y, --yes    Non-interactive; assume yes where possible
  -h, --help   Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1" ;;
  esac
  shift
done

require_root_or_reexec "$@"

# Registry-driven removal of helper-managed files (see uninstall_all in lib/common.sh)
uninstall_all
