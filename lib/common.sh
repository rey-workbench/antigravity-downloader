#!/usr/bin/env bash
# Antigravity Linux Common Library (Single Source of Truth & Core Utilities)
# Defines product metadata, platform resolution, and shared helpers.
set -euo pipefail

# ==============================================================================
# 1. Platform Detection
# ==============================================================================
if [ "$(uname -s)" != "Linux" ]; then
  printf 'ERROR: %s\n' "This script is for Linux only." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64)  AG_PLATFORM="linux-x64"; DESKTOP_TOP="Antigravity-x64" ;;
  aarch64|arm64) AG_PLATFORM="linux-arm"; DESKTOP_TOP="Antigravity-arm64" ;;
  *)
    printf 'ERROR: %s\n' "Unsupported CPU architecture: $(uname -m). Google currently provides x64 and ARM64 Linux builds." >&2
    exit 1
    ;;
esac

# ==============================================================================
# 2. Product Registry (Single Source of Truth)
# ==============================================================================
PRODUCTS=(desktop ide)

product_meta() {
  local id="$1" key="$2"
  case "$id:$key" in
    desktop:label)         printf '%s\n' "Antigravity 2.0" ;;
    desktop:bin)           printf '%s\n' "antigravity" ;;
    desktop:root)          printf '%s\n' "/opt/antigravity" ;;
    desktop:archive)       printf '%s\n' "Antigravity.tar.gz" ;;
    desktop:top)           printf '%s\n' "$DESKTOP_TOP" ;;
    desktop:sub)           printf '%s\n' "$DESKTOP_TOP" ;;
    desktop:exec_arg)      printf '%s\n' "%U" ;;
    desktop:mime)          printf '%s\n' "" ;;
    desktop:markers)       printf '%s\n' "antigravity-2" ;;
    desktop:next_markers)  printf '%s\n' "antigravity-cli" ;;
    desktop:patterns)      printf '%s\n' "Antigravity\.tar\.gz" ;;

    ide:label)             printf '%s\n' "Antigravity IDE" ;;
    ide:bin)               printf '%s\n' "antigravity-ide" ;;
    ide:root)              printf '%s\n' "/opt/antigravity-ide" ;;
    ide:archive)           printf '%s\n' "Antigravity-IDE.tar.gz" ;;
    ide:top)               printf '%s\n' "Antigravity IDE" ;;
    ide:sub)               printf '%s\n' "Antigravity-IDE" ;;
    ide:exec_arg)          printf '%s\n' "%F" ;;
    ide:mime)              printf '%s\n' "inode/directory;text/plain;application/x-code-workspace;application/x-antigravity-workspace;x-scheme-handler/antigravity-ide;" ;;
    ide:markers)           printf '%s\n' "antigravity-ide" ;;
    ide:next_markers)      printf '%s\n' "antigravity-sdk" ;;
    ide:patterns)          printf '%s\n' "Antigravity%20IDE\.tar\.gz|Antigravity\+IDE\.tar\.gz|Antigravity IDE\.tar\.gz" ;;

    *) err "Unknown product metadata: $id:$key" ;;
  esac
}

# ==============================================================================
# 3. System Helpers
# ==============================================================================
log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "Required command not found: $1"; }

require_root_or_reexec() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  local installer_url="${ANTIGRAVITY_LINUX_INSTALLER_URL:-}"
  if command -v sudo >/dev/null 2>&1 && [ -n "${BASH_SOURCE[1]:-}" ] && [ -r "${BASH_SOURCE[1]}" ] && [ "${BASH_SOURCE[1]}" != "bash" ] && [ "${BASH_SOURCE[1]}" != "sh" ]; then
    exec sudo -E env "ANTIGRAVITY_LINUX_INSTALLER_URL=$installer_url" bash "${BASH_SOURCE[1]}" "$@"
  fi
  err "This command needs root. Re-run with: sudo -E bash <script>"
}

# Only accept tarball URLs from Google's official Antigravity hosts.
is_official_url() {
  case "$1" in
    https://antigravity.google/*|https://*.antigravity.google/*) return 0 ;;
    *) return 1 ;;
  esac
}

safe_replace_dir() {
  local newdir="$1" target="$2" prev="${2}.previous"
  rm -rf "$prev"
  if [ -d "$target" ]; then
    mv "$target" "$prev"
  fi
  if ! mv "$newdir" "$target"; then
    if [ -d "$prev" ] && [ ! -d "$target" ]; then
      mv "$prev" "$target"
      warn "Swap failed; previous installation restored at $target"
    fi
    err "Failed to move staged installation into place at $target"
  fi
  rm -rf "$prev"
}

fix_chrome_sandbox() {
  local sandbox="$1"
  if [ -f "$sandbox" ]; then
    chown root:root "$sandbox"
    chmod 4755 "$sandbox"
  fi
}

refresh_desktop_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
  fi
}

installed_version() {
  local file="$1"
  cat "$file" 2>/dev/null || true
}

# Download from Google's official hosts only; verify gzip integrity; record sha256.
fast_download() {
  local url="$1" dest="$2"
  if ! is_official_url "$url"; then
    err "Refusing to download from a non-official URL: $url"
  fi
  if command -v aria2c >/dev/null 2>&1; then
    local dir filename
    dir="$(dirname "$dest")"
    filename="$(basename "$dest")"
    aria2c -q --show-console-readout=false --summary-interval=0 \
      -x 8 -s 8 -j 8 -k 1M --allow-overwrite=true --check-certificate=true \
      -d "$dir" -o "$filename" "$url" \
      || err "aria2c download failed: $url"
  else
    curl -fsSL --retry 3 -o "$dest" "$url" \
      || err "Download failed: $url"
  fi
  if [ ! -s "$dest" ]; then
    err "Downloaded file is empty: $url"
  fi
  # A corrupted or tampered .tar.gz must not reach extraction (runs as root).
  if [ "$(head -c 2 "$dest" | od -An -tx1 | tr -d ' \n')" != "1f8b" ]; then
    err "Downloaded file is not a valid gzip archive: $url"
  fi
  if command -v gzip >/dev/null 2>&1; then
    gzip -t "$dest" || err "Downloaded archive failed gzip integrity check: $url"
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$dest" | awk '{print $1}' > "${dest}.sha256"
  fi
}

# ==============================================================================
# 4. Download Resolver
# ==============================================================================
DOWNLOAD_PAGE="https://antigravity.google/download"

resolve_download_page() {
  local tmpdir="$1"
  local html="$tmpdir/download.html"
  curl -fsSL --compressed --retry 3 -o "$html" "$DOWNLOAD_PAGE"
  printf '%s\n' "$html"
}

resolve_download() {
  local page_file="$1"
  local id="$2"
  local label markers next_markers patterns
  label="$(product_meta "$id" label)"
  markers="$(product_meta "$id" markers)"
  next_markers="$(product_meta "$id" next_markers)"
  patterns="$(product_meta "$id" patterns)"

  python3 - "$page_file" "$AG_PLATFORM" "$label" "$markers" "$next_markers" "$patterns" <<'PY'
import html, re, sys
from pathlib import Path
from urllib.parse import unquote

page_path = Path(sys.argv[1])
platform = sys.argv[2]
label = sys.argv[3]
raw_markers = sys.argv[4].split(',')
raw_next_markers = sys.argv[5].split(',')
filename_patterns = [p.strip() for p in sys.argv[6].split('|')]

markers = [f'id="{m}"' for m in raw_markers] + [f"id='{m}'" for m in raw_markers]
next_markers = [f'id="{m}"' for m in raw_next_markers] + [f"id='{m}'" for m in raw_next_markers]

content = page_path.read_text(errors='replace')

def version_from_url(url):
    decoded = unquote(url)
    for pattern in (r'/antigravity-hub/([^/]+)/', r'/stable/([^/]+)/', r'/(\d+\.\d+\.\d+(?:-[^/]+)?)/'):
        m = re.search(pattern, decoded)
        if m:
            return m.group(1).split('-', 1)[0]
    return 'unknown'

norm_text = html.unescape(content).replace('\\/', '/')
sections = []
for m in markers:
    start = norm_text.find(m)
    if start != -1:
        for nm in next_markers:
            end = norm_text.find(nm, start)
            if end != -1:
                sections.append(norm_text[start:end])
                break
        else:
            sections.append(norm_text[start:])
        break
sections.append(norm_text)

url = None
for section in sections:
    for filename_re in filename_patterns:
        pattern = r'https?://[^"\'\s<>)]*/' + re.escape(platform) + r'/' + filename_re
        matches = re.findall(pattern, section)
        if matches:
            url = matches[-1]
            break
    if url:
        break

if not url:
    sys.exit(f'Could not find official {label} tarball for {platform} on official Google download page')
if not (url.startswith('https://antigravity.google/') or '.antigravity.google/' in url):
    sys.exit(f'Refusing non-official {label} download URL: {url}')

print(version_from_url(url), url)
PY
}

show_status() {
  log "Antigravity Linux status"
  for id in "${PRODUCTS[@]}"; do
    local label bin root ver_file sha_file
    label="$(product_meta "$id" label)"
    bin="$(product_meta "$id" bin)"
    root="$(product_meta "$id" root)"
    ver_file="$root/.antigravity-linux-version"
    sha_file="$root/.antigravity-linux-sha256"
    if [ -x "/usr/local/bin/$bin" ]; then
      log "- $label: installed ($(installed_version "$ver_file"))"
      if [ -s "$sha_file" ]; then
        log "  Tarball sha256: $(cat "$sha_file")"
      fi
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
}

# Derive every path from the product registry so uninstall cannot drift.
uninstall_all() {
  local root bin
  for id in "${PRODUCTS[@]}"; do
    bin="$(product_meta "$id" bin)"
    root="$(product_meta "$id" root)"
    rm -rf "$root" "${root}.new" "${root}.previous"
    rm -f "/usr/local/bin/$bin" "/usr/share/applications/$bin.desktop" \
          "/usr/share/icons/hicolor/512x512/apps/$bin.png"
  done
  rm -f /usr/local/bin/antigravity-linux
  refresh_desktop_caches
  log "Removed helper-managed Antigravity files."
}

asar_extract_icon_png() {
  local asar="$1" out="$2"
  python3 - "$asar" "$out" <<'PY'
import json, struct, sys
from pathlib import Path
asar = Path(sys.argv[1])
out = Path(sys.argv[2])
with asar.open('rb') as f:
    f.read(4)
    header_size = struct.unpack('<I', f.read(4))[0]
    f.read(4)
    json_size = struct.unpack('<I', f.read(4))[0]
    header = json.loads(f.read(json_size).decode())
icon = header.get('files', {}).get('icon.png')
if not icon:
    raise SystemExit('icon.png not found in app.asar')
with asar.open('rb') as f:
    f.seek(8 + header_size + int(icon['offset']))
    out.write_bytes(f.read(int(icon['size'])))
PY
}

install_app_icon() {
  local id="$1" install_dir="$2" dest="$3"
  if [ "$id" = "desktop" ] && [ -f "$install_dir/resources/app.asar" ]; then
    asar_extract_icon_png "$install_dir/resources/app.asar" "$dest" || warn "Could not extract desktop icon; continuing."
  elif [ "$id" = "ide" ] && [ -f "$install_dir/resources/app/resources/linux/code.png" ]; then
    install -m 0644 "$install_dir/resources/app/resources/linux/code.png" "$dest"
  fi
}
