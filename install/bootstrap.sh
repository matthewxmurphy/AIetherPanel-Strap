#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export NEEDRESTART_MODE="${NEEDRESTART_MODE:-a}"

INSTALL_SOURCE_ROOT="${AETHERPANEL_INSTALL_SOURCE_ROOT:-https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/main}"
TMP_DIR="$(mktemp -d /tmp/aetherpanel-bootstrap.XXXXXX)"
INSTALLER_PATH="${TMP_DIR}/aetherpanel-install.sh"

log() {
  printf '[bootstrap] %s\n' "$*"
}

fail() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "Run this bootstrap as root."
  fi
}

cleanup() {
  rm -rf "${TMP_DIR}"
}

restart_ssh_service() {
  local service_name=""

  for candidate in ssh sshd; do
    if systemctl list-unit-files "${candidate}.service" --no-legend >/dev/null 2>&1; then
      service_name="${candidate}"
      break
    fi
  done

  if [ -z "${service_name}" ]; then
    fail "Unable to determine SSH service name for restart."
  fi

  log "Restarting SSH service (${service_name})"
  systemctl restart "${service_name}.service"
}

update_packages() {
  log "Updating package lists"
  apt-get update -y

  log "Upgrading packages"
  apt-get upgrade -y

  log "Cleaning up"
  apt-get autoremove -y
  apt-get clean
}

harden_ssh() {
  local sshd_config="/etc/ssh/sshd_config"
  local sshd_config_new="/etc/ssh/sshd_config.new"

  log "Hardening SSH configuration"

  if [ ! -f "$sshd_config" ]; then
    fail "SSH config not found at $sshd_config"
  fi

  sed -E \
      -e 's/^#?PermitRootLogin.*/PermitRootLogin no/' \
      -e 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' \
      -e 's/^#?PermitEmptyPasswords.*/PermitEmptyPasswords no/' \
      -e 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
      "$sshd_config" > "$sshd_config_new"

  if ! diff -q "$sshd_config" "$sshd_config_new" >/dev/null 2>&1; then
    mv "$sshd_config" "${sshd_config}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$sshd_config_new" "$sshd_config"
    chmod 644 "$sshd_config"

    restart_ssh_service
  else
    rm -f "$sshd_config_new"
  fi
}

main() {
  require_root
  update_packages
  harden_ssh

  trap cleanup EXIT

  log "Downloading installer"
  curl -fsSL "${INSTALL_SOURCE_ROOT%/}/install/aetherpanel-install.sh" -o "${INSTALLER_PATH}"
  chmod +x "${INSTALLER_PATH}"

  log "Running installer"
  exec bash "${INSTALLER_PATH}" "$@"
}

main "$@"
