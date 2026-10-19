#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export NEEDRESTART_MODE="${NEEDRESTART_MODE:-a}"

# This audited source identity is not a release claim. Do not replace its
# content hashes with values downloaded from an untrusted source or manifest.
AUDITED_STAGE_TWO_SOURCE_ROOT="https://raw.githubusercontent.com/matthewxmurphy/AIetherPanel-Strap/25a19882d204dfba392090f84d563d8df9d4038c"
AUDITED_STAGE_TWO_SHA256="1f0c5d6c75e782c8ffbe62c4e92c5063ab381bb1bb4e63fe4c40471c3b330b00"
BOOTSTRAP_SOURCE_ROOT="${AIETHERPANEL_BOOTSTRAP_SOURCE_ROOT:-${AUDITED_STAGE_TWO_SOURCE_ROOT}}"
STAGE_TWO_SOURCE_ROOT="${AETHERPANEL_INSTALL_SOURCE_ROOT:-${AIETHERPANEL_STAGE_TWO_SOURCE_ROOT:-${AUDITED_STAGE_TWO_SOURCE_ROOT}}}"
STAGE_TWO_SHA256="${AIETHERPANEL_STAGE_TWO_SHA256:-${AUDITED_STAGE_TWO_SHA256}}"
STAGE_TWO_SHA256_EXPLICIT="${AIETHERPANEL_STAGE_TWO_SHA256:+1}"
STAGE_TWO_SERVICE_SHA256="${AIETHERPANEL_STAGE_TWO_SERVICE_SHA256:-}"
STAGE_TWO_CONTROLLER_SHA256="${AIETHERPANEL_STAGE_TWO_CONTROLLER_SHA256:-}"
STAGE_TWO_CONTROLLER_TAG="${AETHERPANEL_CONTROLLER_BUNDLE_TAG:-controller-ready-stable-livewire}"
TMP_DIR=""
INSTALLER_PATH=""
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
      --stage-two-source-root|--install-source-root)
        [ $# -ge 2 ] || fail "--stage-two-source-root requires a value."
        STAGE_TWO_SOURCE_ROOT="${2:-}"
        shift 2
        ;;
      --stage-two-sha256)
        [ $# -ge 2 ] || fail "--stage-two-sha256 requires a value."
        STAGE_TWO_SHA256="${2:-}"
        STAGE_TWO_SHA256_EXPLICIT="1"
        shift 2
        ;;
      --stage-two-service-sha256)
        [ $# -ge 2 ] || fail "--stage-two-service-sha256 requires a value."
        STAGE_TWO_SERVICE_SHA256="${2:-}"
        shift 2
        ;;
      --stage-two-controller-sha256)
        [ $# -ge 2 ] || fail "--stage-two-controller-sha256 requires a value."
        STAGE_TWO_CONTROLLER_SHA256="${2:-}"
        shift 2
        ;;
      --stage-two-source-root=*|--install-source-root=*)
        fail "Use --stage-two-source-root URL so its integrity inputs are checked together."
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
  --stage-two-source-root URL   HTTPS mirror of the audited stage-two source
  --stage-two-sha256 HASH       Trusted audited installer digest (required for a custom mirror)
  --stage-two-service-sha256 HASH     Trusted missing service-template digest
  --stage-two-controller-sha256 HASH  Trusted missing controller-bundle digest
  --run-stage-two               Verify every required asset before stage-two execution
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
  if [ -n "${TMP_DIR}" ]; then
    rm -rf "${TMP_DIR}"
  fi
  if [ -n "${SSH_SOURCE_CACHE}" ]; then
    rm -f "${SSH_SOURCE_CACHE}"
  fi
}

validate_stage_two_integrity() {
  [ "${RUN_STAGE_TWO}" = "1" ] || return 0
  STAGE_TWO_SOURCE_ROOT="${STAGE_TWO_SOURCE_ROOT%/}"
  local source_pattern='^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?(/[A-Za-z0-9._~-]+)*$'
  [[ "${STAGE_TWO_SOURCE_ROOT}" =~ ${source_pattern} ]] || fail "Stage-two source must be an HTTPS base URL without credentials, query, fragment or shell characters."

  [[ "${STAGE_TWO_SOURCE_ROOT}/" != *"/../"* && "${STAGE_TWO_SOURCE_ROOT}/" != *"/./"* ]] || fail "Stage-two source must not contain relative path components."

  if [[ "${STAGE_TWO_SOURCE_ROOT}" == https://raw.githubusercontent.com/* ]]; then
    local immutable_pattern='^https://raw[.]githubusercontent[.]com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/[0-9a-f]{40}(/[A-Za-z0-9._~-]+)*$'
    [[ "${STAGE_TWO_SOURCE_ROOT}" =~ ${immutable_pattern} ]] || fail "GitHub stage-two source must use a full immutable commit, not a branch or tag."
  fi
  if [ "${STAGE_TWO_SOURCE_ROOT}" != "${AUDITED_STAGE_TWO_SOURCE_ROOT}" ] && [ "${STAGE_TWO_SHA256_EXPLICIT}" != "1" ]; then
    fail "Custom stage-two sources require an explicit trusted --stage-two-sha256."
  fi

  local variable=""
  for variable in STAGE_TWO_SHA256 STAGE_TWO_SERVICE_SHA256 STAGE_TWO_CONTROLLER_SHA256; do
    [[ "${!variable}" =~ ^[A-Fa-f0-9]{64}$ ]] || fail "${variable} requires a trusted SHA256. The audited source lacks the service template and controller bundle; obtain their complete reviewed payload and digests before stage two."
    printf -v "${variable}" '%s' "${!variable,,}"
  done
  [ "${STAGE_TWO_SHA256}" = "${AUDITED_STAGE_TWO_SHA256}" ] || fail "This bootstrap supports only the audited stage-two script and dependency graph. Review a changed installer before changing its trust contract."
  [[ "${STAGE_TWO_CONTROLLER_TAG}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "Controller bundle tag must be one safe path component."
}

stage_two_asset() {
  local relative="$1"
  local expected="$2"
  local destination="${TMP_DIR}/source/${relative}"
  local partial="${destination}.part"
  local actual=""

  mkdir -p "$(dirname "${destination}")"
  if ! curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 120 "${STAGE_TWO_SOURCE_ROOT}/${relative}" --output "${partial}"; then
    fail "Stage-two asset download failed: ${relative}. No stage-two code was executed."
  fi
  actual="$(sha256sum "${partial}")" || fail "Could not verify stage-two asset: ${relative}."
  [ "${actual%% *}" = "${expected}" ] || fail "Stage-two asset SHA256 mismatch: ${relative}. No stage-two code was executed."
  mv "${partial}" "${destination}"
}

prepare_verified_stage_two() {
  TMP_DIR="$(mktemp -d /tmp/aetherpanel-bootstrap.XXXXXX)"
  INSTALLER_PATH="${TMP_DIR}/source/install/aetherpanel-install.sh"
  stage_two_asset "install/aetherpanel-install.sh" "${STAGE_TWO_SHA256}"

  # The audited installer discovers a local source tree using ui/ and conf/.
  # Stage verified real source files there so it cannot fetch mutable helpers later.
  local digest=""
  local relative=""
  while read -r digest relative; do
    stage_two_asset "${relative}" "${digest}"
  done <<'ASSETS'
e00c835c3c2387d25afe4cf9c2c3e593546a13e388abca1c427de602cc236604 install/steps/10-preflight.sh
1f07035aa49ba5d41806454798accaa75b4c83a856efda91b2212043aa5bc85a install/steps/20-packages.sh
20b4fdacd0dedae7c98585bd8d2b7ec9095578e64e65136afc60233893befc35 install/steps/30-tailscale.sh
e2a3a065332eb6049ca3db03a9f9e747ee147603ff6ce6f4f7d43a9d2b232309 install/steps/40-panel-files.sh
52188bd1eefad87e6453ee6f09c82eceaa778b156632e92a2133ab904be97f6c install/steps/50-services.sh
4c3fd322b7c16078b800399063acda277a5370326ebe0e6935732bf5ea0fc312 conf/lighttpd-controller.conf.template
8fcbb3085b8f3c7e76a7e85694e7b1d2e583e017a52830021245f44d61471ad3 ui/public/index.php
ASSETS
  stage_two_asset "conf/aetherpanel-lighttpd.service.template" "${STAGE_TWO_SERVICE_SHA256}"
  stage_two_asset "controller/dist/controller-runtime/${STAGE_TWO_CONTROLLER_TAG}.tar.gz" "${STAGE_TWO_CONTROLLER_SHA256}"
  export AETHERPANEL_INSTALL_SOURCE_ROOT="${STAGE_TWO_SOURCE_ROOT}"
  export AETHERPANEL_CONTROLLER_BUNDLE_TAG="${STAGE_TWO_CONTROLLER_TAG}"
}

default_fleet_authorized_keys() {
  cat <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEoGV7fX95o5NlUOc/gxLaoj/j/3bqcSAvGwWZRHudvU aietherpanel@t0001
EOF
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
  if ! curl -fsSL "${FLEET_SSH_PUB_URL}" -o "${SSH_SOURCE_CACHE}"; then
    log "Falling back to bundled fleet operator key"
    default_fleet_authorized_keys >"${SSH_SOURCE_CACHE}"
  fi
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
  trap cleanup EXIT
  parse_args "$@"
  validate_stage_two_integrity
  require_root
  if [ "${RUN_STAGE_TWO}" = "1" ]; then
    log "Verifying stage-two installer and required payload"
    prepare_verified_stage_two
  fi
  install_tailscale
  ensure_operator_user
  resolve_ssh_pub_source
  append_authorized_keys
  ensure_tailscale_connected
  ensure_aietherpanel_apt_repo
  harden_ssh

  if [ "${RUN_STAGE_TWO}" != "1" ]; then
    log "Bootstrap prep complete. Tailscale, operator access, and the AIetherPanel apt repo are ready."
    exit 0
  fi

  if ! stage_two_has_ssh_pub_arg; then
    PASSTHROUGH_ARGS+=("--ssh-pub-url" "$(effective_fleet_ssh_pub_url)")
  fi

  log "Running installer"
  bash "${INSTALLER_PATH}" "${PASSTHROUGH_ARGS[@]}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
