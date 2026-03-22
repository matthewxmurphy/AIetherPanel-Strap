#!/usr/bin/env bash
set -euo pipefail

INSTALL_SOURCE_ROOT="${AETHERPANEL_INSTALL_SOURCE_ROOT:-https://raw.githubusercontent.com/matthewxmurphy/AetherPanel-Strap/main}"
TMP_DIR="$(mktemp -d /tmp/aetherpanel-bootstrap.XXXXXX)"
INSTALLER_PATH="${TMP_DIR}/aetherpanel-install.sh"

cleanup() {
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

curl -fsSL "${INSTALL_SOURCE_ROOT%/}/install/aetherpanel-install.sh" -o "${INSTALLER_PATH}"
chmod +x "${INSTALLER_PATH}"
exec bash "${INSTALLER_PATH}" "$@"
