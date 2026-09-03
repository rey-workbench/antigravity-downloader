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

log "Antigravity Linux status"
for id in "${PRODUCTS[@]}"; do
  label="$(product_meta "$id" label)"
  bin="$(product_meta "$id" bin)"
  root="$(product_meta "$id" root)"
  ver_file="$root/.antigravity-linux-version"
  if [ -x "/usr/local/bin/$bin" ]; then
    log "- $label: installed ($(installed_version "$ver_file"))"
    log "  Command: /usr/local/bin/$bin"
  else
    log "- $label: not installed by this helper"
  fi
done

if [ -x /usr/local/bin/antigravity-linux ]; then
  log "- Update helper: installed"
else
  log "- Update helper: not installed"
fi
