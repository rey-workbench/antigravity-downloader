#!/usr/bin/env bash
# Antigravity Linux Installer
# Installs/updates Google Antigravity 2.0 and Antigravity IDE on Linux.
# Resolves latest official Google tarballs from https://antigravity.google/download.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  # shellcheck source=lib/common.sh
  source "$SCRIPT_DIR/lib/common.sh"
else
  BASE_URL="${ANTIGRAVITY_LINUX_BASE_URL:-${ANTIGRAVITY_LINUX_INSTALLER_URL%/*}}"
  [ -n "$BASE_URL" ] || BASE_URL="https://rey-workbench.github.io/antigravity-downloader"
  source <(curl -fsSL --retry 3 "$BASE_URL/lib/common.sh")
fi

# ==============================================================================
# Global State & CLI Parsing
# ==============================================================================
ORIGINAL_ARGS=("$@")
PROJECT_NAME="antigravity-linux"
CLI_INSTALLER="https://antigravity.google/cli/install.sh"
INSTALLER_URL="${ANTIGRAVITY_LINUX_INSTALLER_URL:-}"
TMP_CLEANUP_DIR=""

INSTALL_DESKTOP=1
INSTALL_IDE=0
INSTALL_CLI=0
INSTALL_DEPS=1
DO_UNINSTALL=0
DO_STATUS=0
DO_PRINT_DOWNLOADS=0
FORCE=0
YES=0

is_product_selected() {
  case "$1" in
    desktop) [ "$INSTALL_DESKTOP" -eq 1 ] ;;
    ide)     [ "$INSTALL_IDE" -eq 1 ] ;;
    *)       return 1 ;;
  esac
}

cleanup() {
  if [ -n "${TMP_CLEANUP_DIR:-}" ] && [ -d "$TMP_CLEANUP_DIR" ]; then
    rm -rf "$TMP_CLEANUP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Antigravity Linux Installer

Usage:
  install.sh [install|update] [options]
  install.sh --status
  install.sh --print-downloads
  install.sh --uninstall

Default:
  Installs or updates Antigravity 2.0 desktop app system-wide.

Options:
  --desktop              Install/update Antigravity 2.0 desktop app only (default)
  --ide                  Install/update Antigravity IDE only
  --all                  Install/update Antigravity 2.0 desktop app + Antigravity IDE
  --cli                  Also run Google's official Antigravity CLI installer
  --no-deps, --no-apt    Do not install package dependencies automatically
  --force                Reinstall even when the recorded version matches
  --install-url URL      Store URL used by the antigravity-linux update command
  --status               Show installed helper-managed apps and versions
  --print-downloads      Print the resolved official Google tarball URLs
  --uninstall            Remove helper-managed Antigravity desktop/IDE files
  -y, --yes              Non-interactive; assume yes where possible
  -h, --help             Show this help

Recommended GitHub Pages one-liner:
  INSTALLER_URL="https://YOUR_GITHUB_USERNAME.github.io/antigravity-linux/install.sh"; \
  curl -fsSL "$INSTALLER_URL" | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL="$INSTALLER_URL" bash -s -- --all

Update after install:
  sudo antigravity-linux update --all
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    install|update) ;;
    --desktop) INSTALL_DESKTOP=1; INSTALL_IDE=0 ;;
    --ide) INSTALL_DESKTOP=0; INSTALL_IDE=1 ;;
    --all) INSTALL_DESKTOP=1; INSTALL_IDE=1 ;;
    --cli) INSTALL_CLI=1 ;;
    --no-apt|--no-deps) INSTALL_DEPS=0 ;;
    --force) FORCE=1 ;;
    --install-url)
      shift
      [ $# -gt 0 ] || err "--install-url needs a URL"
      INSTALLER_URL="$1"
      ;;
    --status) DO_STATUS=1 ;;
    --print-downloads) DO_PRINT_DOWNLOADS=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    -y|--yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1" ;;
  esac
  shift
done

# ==============================================================================
# Installer Engine
# ==============================================================================
install_deps() {
  [ "$INSTALL_DEPS" -eq 1 ] || return 0
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y ca-certificates curl tar python3 gzip sha256sum desktop-file-utils xdg-utils aria2 \
      || apt-get install -y ca-certificates curl tar python3 gzip sha256sum desktop-file-utils xdg-utils \
      || err "Dependency installation failed; fix the errors above or re-run with --no-deps"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl tar python3 gzip coreutils-single coreutils desktop-file-utils xdg-utils aria2 \
      || dnf install -y curl tar python3 gzip coreutils desktop-file-utils xdg-utils \
      || err "Dependency installation failed; fix the errors above or re-run with --no-deps"
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm --needed curl tar python gzip coreutils desktop-file-utils xdg-utils aria2 \
      || err "Dependency installation failed; fix the errors above or re-run with --no-deps"
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install curl tar python3 gzip coreutils desktop-file-utils xdg-utils aria2 \
      || err "Dependency installation failed; fix the errors above or re-run with --no-deps"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl tar python3 gzip libstdc++ gcompat desktop-file-utils xdg-utils aria2 \
      || apk add --no-cache curl tar python3 gzip libstdc++ gcompat desktop-file-utils xdg-utils \
      || err "Dependency installation failed; fix the errors above or re-run with --no-deps"
  else
    for c in curl tar python3 gzip sha256sum; do need "$c"; done
  fi
}

download_app() {
  local id="$1" tmpdir="$2" page_file="$3"
  local label bin root archive install_sub target version_file version url
  label="$(product_meta "$id" label)"
  bin="$(product_meta "$id" bin)"
  root="$(product_meta "$id" root)"
  archive="$(product_meta "$id" archive)"
  install_sub="$(product_meta "$id" sub)"
  target="$root/$install_sub/$bin"
  version_file="$root/.antigravity-linux-version"

  read -r version url < <(resolve_download "$page_file" "$id")
  if [ "$FORCE" -eq 0 ] && [ -x "$target" ] && [ "$(installed_version "$version_file")" = "$version" ]; then
    return 0
  fi
  if [ ! -f "$tmpdir/$archive" ]; then
    log "Downloading $label $version for $AG_PLATFORM from Google..."
    fast_download "$url" "$tmpdir/$archive"
  fi
}

install_app() {
  local id="$1" tmpdir="$2" page_file="$3"
  local label bin root archive top_expected install_sub exec_arg mime
  label="$(product_meta "$id" label)"
  bin="$(product_meta "$id" bin)"
  root="$(product_meta "$id" root)"
  archive="$(product_meta "$id" archive)"
  top_expected="$(product_meta "$id" top)"
  install_sub="$(product_meta "$id" sub)"
  exec_arg="$(product_meta "$id" exec_arg)"
  mime="$(product_meta "$id" mime)"

  local version url
  read -r version url < <(resolve_download "$page_file" "$id")
  local target="$root/$install_sub/$bin"
  local version_file="$root/.antigravity-linux-version"

  if [ "$FORCE" -eq 0 ] && [ -x "$target" ] && [ "$(installed_version "$version_file")" = "$version" ]; then
    log "$label $version is already installed."
    return
  fi

  download_app "$id" "$tmpdir" "$page_file"
  local top_dir
  top_dir=$(tar -tzf "$tmpdir/$archive" | sed -n '1{s#/.*##;p;q}')
  [ "$top_dir" = "$top_expected" ] || err "Unexpected $label archive layout: $top_dir"
  tar -xzf "$tmpdir/$archive" -C "$tmpdir"
  [ -x "$tmpdir/$top_dir/$bin" ] || err "$label launcher not found inside tarball."

  # Clean any staging directory left over by an interrupted previous run.
  rm -rf "${root}.new"
  mkdir -p "${root}.new/$install_sub"
  cp -a "$tmpdir/$top_dir/." "${root}.new/$install_sub/"
  printf '%s\n' "$version" > "${root}.new/.antigravity-linux-version"
  printf '%s\n' "$url" > "${root}.new/.antigravity-linux-source-url"
  [ -f "$tmpdir/$archive.sha256" ] && \
    cp "$tmpdir/$archive.sha256" "${root}.new/.antigravity-linux-sha256"
  fix_chrome_sandbox "${root}.new/$install_sub/chrome-sandbox"
  safe_replace_dir "${root}.new" "$root"

  ln -sfn "$root/$install_sub/$bin" "/usr/local/bin/$bin"
  mkdir -p /usr/share/icons/hicolor/512x512/apps /usr/share/applications

  install_app_icon "$id" "$root/$install_sub" "/usr/share/icons/hicolor/512x512/apps/$bin.png"

  local mime_line=""
  [ -n "$mime" ] && mime_line="MimeType=$mime"

  cat > "/usr/share/applications/$bin.desktop" <<DESKTOP
[Desktop Entry]
Name=$label
Comment=Google $label
Exec=/usr/local/bin/$bin $exec_arg
Icon=$bin
Terminal=false
Type=Application
Categories=Development;IDE;
${mime_line}
StartupNotify=true
StartupWMClass=$bin
DESKTOP

  refresh_desktop_caches
  log "Installed $label $version at $root/$install_sub"
}

install_manager_command() {
  local installer_url="${INSTALLER_URL:-https://rey-workbench.github.io/antigravity-downloader/install.sh}"
  cat > /usr/local/bin/antigravity-linux <<SH
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_URL="${installer_url}"
[ -n "\$SCRIPT_URL" ] || SCRIPT_URL="https://rey-workbench.github.io/antigravity-downloader/install.sh"
if [ "\$(id -u)" -eq 0 ]; then
  curl -fsSL --retry 3 "\$SCRIPT_URL" | env ANTIGRAVITY_LINUX_INSTALLER_URL="\$SCRIPT_URL" bash -s -- "\$@"
else
  curl -fsSL --retry 3 "\$SCRIPT_URL" | sudo -E env ANTIGRAVITY_LINUX_INSTALLER_URL="\$SCRIPT_URL" bash -s -- "\$@"
fi
SH
  chmod +x /usr/local/bin/antigravity-linux
}

print_downloads() {
  need curl
  need python3
  local tmp_parent="${TMPDIR:-/tmp}"
  local tmpdir
  tmpdir=$(mktemp -d "$tmp_parent/$PROJECT_NAME.XXXXXX")
  TMP_CLEANUP_DIR="$tmpdir"
  local page_file
  page_file=$(resolve_download_page "$tmpdir")
  for id in "${PRODUCTS[@]}"; do
    if is_product_selected "$id"; then
      local label version url
      label="$(product_meta "$id" label)"
      read -r version url < <(resolve_download "$page_file" "$id")
      log "$label $version: $url"
    fi
  done
  rm -rf "$tmpdir"
  TMP_CLEANUP_DIR=""
}

print_success_summary() {
  log ""
  log "Antigravity Linux install complete."
  log ""
  log "Installed:"
  for id in "${PRODUCTS[@]}"; do
    if is_product_selected "$id"; then
      local label bin
      label="$(product_meta "$id" label)"
      bin="$(product_meta "$id" bin)"
      log "- $label: /usr/local/bin/$bin"
    fi
  done
  log ""
  log "Manage:"
  log "- Status:    antigravity-linux --status"
  log "- Update:    sudo antigravity-linux update --all"
  log "- Uninstall: sudo antigravity-linux --uninstall"
  if [ -z "$INSTALLER_URL" ]; then
    log ""
    log "Note: antigravity-linux was installed without a stored URL. Re-run this local script for updates or reinstall from a published URL."
  fi
  if [ "$INSTALL_IDE" -eq 1 ]; then
    log ""
    log "Folder open integration: use your file manager's Open With menu."
  fi
}

main() {
  if [ "$DO_STATUS" -eq 1 ]; then
    show_status
    exit 0
  fi

  if [ "$DO_PRINT_DOWNLOADS" -eq 1 ]; then
    print_downloads
    exit 0
  fi

  if [ "$DO_UNINSTALL" -eq 1 ]; then
    require_root_or_reexec "$@"
    uninstall_all
    exit 0
  fi

  require_root_or_reexec "${ORIGINAL_ARGS[@]}"
  install_deps
  local tmp_parent="${TMPDIR:-/var/tmp}"
  mkdir -p "$tmp_parent"
  local tmpdir
  tmpdir=$(mktemp -d "$tmp_parent/$PROJECT_NAME.XXXXXX")
  TMP_CLEANUP_DIR="$tmpdir"
  local page_file
  page_file=$(resolve_download_page "$tmpdir")

  # Concurrent pre-download for selected products
  local pids=()
  for id in "${PRODUCTS[@]}"; do
    if is_product_selected "$id"; then
      download_app "$id" "$tmpdir" "$page_file" &
      pids+=($!)
    fi
  done
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  for id in "${PRODUCTS[@]}"; do
    if is_product_selected "$id"; then
      install_app "$id" "$tmpdir" "$page_file"
    fi
  done

  if [ "$INSTALL_CLI" -eq 1 ]; then
    log "Running Google's official Antigravity CLI installer for the non-root user..."
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-}" != "root" ]; then
      sudo -u "$SUDO_USER" -H bash -lc "curl -fsSL --retry 3 '$CLI_INSTALLER' | bash"
    else
      curl -fsSL --retry 3 "$CLI_INSTALLER" | bash
    fi
  fi
  install_manager_command
  print_success_summary
}

main "$@"
