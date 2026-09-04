# Changelog

## Unreleased

- Downloads are restricted to official `antigravity.google` hosts; non-official URLs abort.
- Tarballs are gzip-integrity-checked before root extraction and their sha256 is recorded (visible via `--status`).
- Failed installs now roll back to the previous version instead of leaving the target missing.
- Old `.previous` backups are cleaned after every successful swap.
- Uninstall now derives every path from the product registry (no more hardcoded path drift).
- Removed the non-functional `--no-nautilus` option and the Nautilus helper remnants.
- Dependency installation failures now abort with a clear message instead of being silently swallowed.
- Removed references to the never-created `update-antigravity` commands; README now shows the working `antigravity-linux update` variants.
- README distro support section now separates tested distros from best-effort support.

## 0.1.0 - Initial public project

- One-command installer for official Google Antigravity 2.0 Linux tarball.
- Optional Antigravity IDE install.
- App menu entries and icons.
- `/usr/local/bin` launchers.
- `antigravity-linux` update helper.
- Folder open integration for Antigravity IDE.
- GitHub Pages landing page and deploy workflow.
