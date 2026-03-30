#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export NEEDRESTART_MODE="${NEEDRESTART_MODE:-a}"

INSTALL_SOURCE_ROOT="${AETHERPANEL_INSTALL_SOURCE_ROOT:-https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/main}"
TMP_DIR="$(mktemp -d /tmp/aetherpanel-bootstrap.XXXXXX)"
INSTALLER_PATH="${TMP_DIR}/aetherpanel-install.sh"
RUN_STAGE_TWO="0"
PASSTHROUGH_ARGS=()
FLEET_SSH_PUB_URL="${AIETHERPANEL_FLEET_SSH_PUB_URL:-}"

log() {
  printf '[bootstrap] %s\n' "$*"
}

fail() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --stage-two-source-root)
        [ $# -ge 2 ] || fail "--stage-two-source-root requires a value."
        INSTALL_SOURCE_ROOT="${2:-}"
        shift 2
        ;;
      --run-stage-two)
        RUN_STAGE_TWO="1"
        shift
        ;;
      --fleet-ssh-pub-url)
        [ $# -ge 2 ] || fail "--fleet-ssh-pub-url requires a value."
        FLEET_SSH_PUB_URL="${2:-}"
        shift 2
        ;;
      -h|--help)
        cat <<'EOF'
AIetherPanel bootstrap

Usage:
  bootstrap.sh [bootstrap-options] [installer-options]

Bootstrap options:
  --stage-two-source-root URL   Source root used to download stage-two installer assets
  --run-stage-two               Run the stage-two installer after bootstrap prep
  --fleet-ssh-pub-url URL       Public key list for controller/operator SSH access on joined nodes

All other arguments are passed through to aetherpanel-install.sh.
EOF
        exit 0
        ;;
      *)
        PASSTHROUGH_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "Run this bootstrap as root."
  fi
}

stage_two_has_ssh_pub_arg() {
  local arg=""

  for arg in "${PASSTHROUGH_ARGS[@]}"; do
    case "$arg" in
      --ssh-pub-source|--ssh-pub-url)
        return 0
        ;;
    esac
  done

  return 1
}

effective_fleet_ssh_pub_url() {
  if [ -n "${FLEET_SSH_PUB_URL}" ]; then
    printf '%s\n' "${FLEET_SSH_PUB_URL}"
    return 0
  fi

  printf '%s/install/fleet-authorized_keys.txt\n' "${INSTALL_SOURCE_ROOT%/}"
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
  parse_args "$@"
  require_root
  update_packages
  harden_ssh

  trap cleanup EXIT

  export AETHERPANEL_INSTALL_SOURCE_ROOT="${INSTALL_SOURCE_ROOT}"

  if [ "${RUN_STAGE_TWO}" != "1" ]; then
    log "Bootstrap prep complete. Skipping installer because --run-stage-two was not provided."
    exit 0
  fi

  log "Downloading installer"
  curl -fsSL "${INSTALL_SOURCE_ROOT%/}/install/aietherpanel-install.sh" -o "${INSTALLER_PATH}"
  chmod +x "${INSTALLER_PATH}"

  if ! stage_two_has_ssh_pub_arg; then
    PASSTHROUGH_ARGS+=("--ssh-pub-url" "$(effective_fleet_ssh_pub_url)")
  fi

  log "Running installer"
  exec bash "${INSTALLER_PATH}" "${PASSTHROUGH_ARGS[@]}"
}

main "$@"
