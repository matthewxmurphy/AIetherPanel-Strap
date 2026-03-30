#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export NEEDRESTART_MODE="${NEEDRESTART_MODE:-a}"

BOOTSTRAP_SOURCE_ROOT="${AIETHERPANEL_BOOTSTRAP_SOURCE_ROOT:-https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/main}"
STAGE_TWO_SOURCE_ROOT="${AETHERPANEL_INSTALL_SOURCE_ROOT:-${AIETHERPANEL_STAGE_TWO_SOURCE_ROOT:-https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/main}}"
TMP_DIR="$(mktemp -d /tmp/aetherpanel-bootstrap.XXXXXX)"
INSTALLER_PATH="${TMP_DIR}/aetherpanel-install.sh"
RUN_STAGE_TWO="0"
PASSTHROUGH_ARGS=()
FLEET_SSH_PUB_URL="${AIETHERPANEL_FLEET_SSH_PUB_URL:-}"
TAILSCALE_AUTHKEY="${AIETHERPANEL_TAILSCALE_AUTHKEY:-}"
TAILSCALE_ARGS="${AIETHERPANEL_TAILSCALE_ARGS:-}"
OPERATOR_USER="${AIETHERPANEL_OPERATOR_USER:-mmurphy}"
SSH_SOURCE_CACHE=""

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
        STAGE_TWO_SOURCE_ROOT="${2:-}"
        shift 2
        ;;
      --run-stage-two)
        RUN_STAGE_TWO="1"
        shift
        ;;
      --tailscale-authkey)
        [ $# -ge 2 ] || fail "--tailscale-authkey requires a value."
        TAILSCALE_AUTHKEY="${2:-}"
        shift 2
        ;;
      --tailscale-args)
        [ $# -ge 2 ] || fail "--tailscale-args requires a value."
        TAILSCALE_ARGS="${2:-}"
        shift 2
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
  --tailscale-authkey KEY       Optional Tailscale auth key for non-interactive bring-up
  --tailscale-args ARGS         Extra arguments passed to tailscale up
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

  printf '%s/install/fleet-authorized_keys.txt\n' "${BOOTSTRAP_SOURCE_ROOT%/}"
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

install_bootstrap_prereqs() {
  log "Installing bootstrap prerequisites"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg jq

  install -d -m 0755 /usr/share/keyrings
}

install_tailscale_repo() {
  local repo_file="/etc/apt/sources.list.d/tailscale.list"
  local codename=""

  if [ -f "$repo_file" ]; then
    return 0
  fi

  . /etc/os-release
  codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  [ -n "$codename" ] || fail "Could not determine Ubuntu codename for the Tailscale repository."

  log "Adding Tailscale apt repository"
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  printf 'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu %s main\n' "$codename" \
    >/etc/apt/sources.list.d/tailscale.list
}

install_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    return 0
  fi

  install_bootstrap_prereqs
  install_tailscale_repo
  log "Installing Tailscale"
  apt-get update -y
  apt-get install -y tailscale
}

ensure_operator_user() {
  if ! id "${OPERATOR_USER}" >/dev/null 2>&1; then
    log "Creating operator user ${OPERATOR_USER}"
    useradd -m -s /bin/bash "${OPERATOR_USER}"
  fi

  usermod -aG sudo "${OPERATOR_USER}"
  install -d -m 0700 -o "${OPERATOR_USER}" -g "${OPERATOR_USER}" "/home/${OPERATOR_USER}/.ssh"
  touch "/home/${OPERATOR_USER}/.ssh/authorized_keys"
  chown "${OPERATOR_USER}:${OPERATOR_USER}" "/home/${OPERATOR_USER}/.ssh/authorized_keys"
  chmod 0600 "/home/${OPERATOR_USER}/.ssh/authorized_keys"

  if [ ! -f "/etc/sudoers.d/90-${OPERATOR_USER}" ]; then
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${OPERATOR_USER}" >/tmp/aetherpanel-sudoers
    install -m 0440 /tmp/aetherpanel-sudoers "/etc/sudoers.d/90-${OPERATOR_USER}"
  fi
}

resolve_ssh_pub_source() {
  if [ -z "${FLEET_SSH_PUB_URL}" ]; then
    FLEET_SSH_PUB_URL="$(effective_fleet_ssh_pub_url)"
  fi

  SSH_SOURCE_CACHE="$(mktemp /tmp/aetherpanel-ssh-pubs.XXXXXX)"
  curl -fsSL "${FLEET_SSH_PUB_URL}" -o "${SSH_SOURCE_CACHE}"
}

append_authorized_keys() {
  local target="/home/${OPERATOR_USER}/.ssh/authorized_keys"
  local line=""

  [ -f "${SSH_SOURCE_CACHE}" ] || return 0

  while IFS= read -r line || [ -n "${line}" ]; do
    line="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "${line}" ] || continue

    if grep -qxF "${line}" "${target}" 2>/dev/null; then
      continue
    fi

    printf '%s\n' "${line}" >>"${target}"
  done <"${SSH_SOURCE_CACHE}"

  chown "${OPERATOR_USER}:${OPERATOR_USER}" "${target}"
  chmod 0600 "${target}"
}

ensure_tailscale_connected() {
  log "Ensuring Tailscale is running"
  systemctl enable --now tailscaled

  if tailscale ip -4 >/dev/null 2>&1 && [ -n "$(tailscale ip -4 | head -n1)" ]; then
    return 0
  fi

  if [ -n "${TAILSCALE_AUTHKEY}" ]; then
    log "Connecting to Tailscale with auth key"
    tailscale up --authkey="${TAILSCALE_AUTHKEY}" ${TAILSCALE_ARGS}
    return 0
  fi

  log "Launching Tailscale sign-in"
  tailscale up ${TAILSCALE_ARGS}
}

ensure_aietherpanel_apt_repo() {
  local repo_base_url=""
  local repo_file="/etc/apt/sources.list.d/aietherpanel.list"
  local repo_line=""
  local current_line=""

  repo_base_url="$(printf '%s' "${STAGE_TWO_SOURCE_ROOT%/}" | sed -E 's#/aietherpanel/?$##')"
  if [ "${repo_base_url}" = "${STAGE_TWO_SOURCE_ROOT%/}" ]; then
    return 0
  fi

  repo_line="deb [trusted=yes] ${repo_base_url%/}/apt stable main"

  if [ -f "${repo_file}" ]; then
    current_line="$(grep -v '^[[:space:]]*#' "${repo_file}" 2>/dev/null | sed '/^[[:space:]]*$/d' | head -n1 || true)"
    if [ "${current_line}" = "${repo_line}" ]; then
      return 0
    fi
  fi

  log "Adding AIetherPanel apt repository"
  printf '%s\n' "${repo_line}" >/tmp/aietherpanel.list
  install -d -m 0755 /etc/apt/sources.list.d
  install -m 0644 /tmp/aietherpanel.list "${repo_file}"
  apt-get update -o Acquire::AllowInsecureRepositories=true || true
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
  install_tailscale
  ensure_operator_user
  resolve_ssh_pub_source
  append_authorized_keys
  ensure_tailscale_connected
  ensure_aietherpanel_apt_repo
  harden_ssh

  trap cleanup EXIT

  export AETHERPANEL_INSTALL_SOURCE_ROOT="${STAGE_TWO_SOURCE_ROOT}"

  if [ "${RUN_STAGE_TWO}" != "1" ]; then
    log "Bootstrap prep complete. Tailscale, operator access, and the AIetherPanel apt repo are ready."
    exit 0
  fi

  log "Downloading installer"
  curl -fsSL "${STAGE_TWO_SOURCE_ROOT%/}/install/aietherpanel-install.sh" -o "${INSTALLER_PATH}"
  chmod +x "${INSTALLER_PATH}"

  if ! stage_two_has_ssh_pub_arg; then
    PASSTHROUGH_ARGS+=("--ssh-pub-url" "$(effective_fleet_ssh_pub_url)")
  fi

  log "Running installer"
  exec bash "${INSTALLER_PATH}" "${PASSTHROUGH_ARGS[@]}"
}

main "$@"
