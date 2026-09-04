#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n lib/common.sh
bash -n install.sh
bash -n uninstall.sh
bash -n status.sh
bash -n docs/lib/common.sh
bash -n docs/install.sh
bash -n docs/uninstall.sh
bash -n docs/status.sh
bash -n scripts/sync-site.sh

for f in install.sh uninstall.sh status.sh lib/common.sh; do
  if ! cmp -s "$f" "docs/$f"; then
    echo "docs/$f is out of sync. Run: bash scripts/sync-site.sh" >&2
    exit 1
  fi
done

bash install.sh --status >/dev/null
bash status.sh >/dev/null

# Installer must clean interrupted .new staging directories before staging again.
if ! grep -qF 'rm -rf "${root}.new"' install.sh; then
  echo "install.sh must clean interrupted .new staging directories." >&2
  exit 1
fi

# Uninstaller must route through the registry-driven uninstall_all.
if ! grep -qE '^uninstall_all$' uninstall.sh; then
  echo "uninstall.sh must call the registry-driven uninstall_all." >&2
  exit 1
fi

# uninstall_all must remove live installs, staging dirs, and previous backups.
if ! grep -qF 'rm -rf "$root" "${root}.new" "${root}.previous"' lib/common.sh; then
  echo "lib/common.sh uninstall_all must remove live, .new, and .previous install directories." >&2
  exit 1
fi

# Downloads must be restricted to official Google Antigravity hosts.
if ! grep -qF 'is_official_url' lib/common.sh; then
  echo "lib/common.sh must restrict downloads to official hosts (is_official_url)." >&2
  exit 1
fi

echo "All checks passed."
