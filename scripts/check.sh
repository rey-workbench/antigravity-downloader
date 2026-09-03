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

if ! grep -q '/opt/antigravity.new' install.sh || ! grep -q '/opt/antigravity-ide.new' install.sh; then
  echo "install.sh uninstall must remove interrupted .new staging directories." >&2
  exit 1
fi

if ! grep -q '/opt/antigravity.new' uninstall.sh || ! grep -q '/opt/antigravity-ide.new' uninstall.sh; then
  echo "uninstall.sh must remove interrupted .new staging directories." >&2
  exit 1
fi

echo "All checks passed."
