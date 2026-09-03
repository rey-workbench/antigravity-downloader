#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$ROOT_DIR/docs/lib"
cp "$ROOT_DIR/install.sh" "$ROOT_DIR/docs/install.sh"
cp "$ROOT_DIR/uninstall.sh" "$ROOT_DIR/docs/uninstall.sh"
cp "$ROOT_DIR/status.sh" "$ROOT_DIR/docs/status.sh"
cp "$ROOT_DIR/lib/common.sh" "$ROOT_DIR/docs/lib/common.sh"

chmod +x "$ROOT_DIR/docs/install.sh" "$ROOT_DIR/docs/uninstall.sh" "$ROOT_DIR/docs/status.sh" "$ROOT_DIR/docs/lib/common.sh"
