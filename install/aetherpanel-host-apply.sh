#!/usr/bin/env bash
set -euo pipefail

PROFILE="${PROFILE:-hybrid}"
NODE_NAME="${NODE_NAME:-$(hostname -s 2>/dev/null || hostname)}"
ROLES="${ROLES:-}"
SSH_PUB_SOURCE="${SSH_PUB_SOURCE:-}"
SSH_PUB_URL="${SSH_PUB_URL:-}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
TAILSCALE_ARGS="${TAILSCALE_ARGS:-}"
OPERATOR_USER="${OPERATOR_USER:-mmurphy}"
SET_HOSTNAME="${SET_HOSTNAME:-0}"
DRY_RUN="${DRY_RUN:-0}"
PROFILE_DESCRIPTION=""
SSH_SOURCE_CACHE=""

usage() {
  cat <<'EOF'
AIetherPanel host baseline apply

Usage:
  aetherpanel-host-apply.sh [options]

Options:
  --profile hybrid|controller|application|app|mail-test|dns|backup|custom
  --roles controller,web,database
  --node-name NAME
  --operator-user USER
  --ssh-pub-source /path/to/public-keys.txt
  --ssh-pub-url URL
  --tailscale-authkey KEY
  --tailscale-args "..."
  --set-hostname
  --dry-run
  -h, --help

Notes:
  - hybrid is the default for the current OCI production nodes.
  - controller is a lean control-panel profile.
  - application is for website/application/database nodes without the controller role.
  - mail-test is the testing baseline for the future mail role.
  - dns is the tiny DNS-only baseline.
  - backup is the Wasabi-target helper baseline.
  - Fail2ban is local. CrowdSec is remote-managed and not installed here.
EOF
}

log() {
  printf '[aetherpanel-host-apply] %s\n' "$*"
}

fail() {
  printf '[aetherpanel-host-apply] ERROR: %s\n' "$*" >&2
  exit 1
}

run_cmd() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  eval "$@"
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --profile)
        PROFILE="${2:-}"; shift 2 ;;
      --roles)
        ROLES="${2:-}"; shift 2 ;;
      --node-name)
        NODE_NAME="${2:-}"; shift 2 ;;
      --operator-user)
        OPERATOR_USER="${2:-}"; shift 2 ;;
      --ssh-pub-source)
        SSH_PUB_SOURCE="${2:-}"; shift 2 ;;
      --ssh-pub-url)
        SSH_PUB_URL="${2:-}"; shift 2 ;;
      --tailscale-authkey)
        TAILSCALE_AUTHKEY="${2:-}"; shift 2 ;;
      --tailscale-args)
        TAILSCALE_ARGS="${2:-}"; shift 2 ;;
      --set-hostname)
        SET_HOSTNAME="1"; shift ;;
      --dry-run)
        DRY_RUN="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        fail "Unknown option: $1" ;;
    esac
  done
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "Run this script as root."
  fi
}

detect_os() {
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ]; then
    fail "Ubuntu is required for the current AIetherPanel host baseline."
  fi
}

apply_profile_defaults() {
  case "$PROFILE" in
    hybrid)
      PROFILE_DESCRIPTION="Hybrid controller/app/database baseline for the current OCI production pair."
      [ -n "$ROLES" ] || ROLES="controller,web,database"
      ;;
    controller)
      PROFILE_DESCRIPTION="Dedicated controller node with the local panel and fleet/operator baseline."
      [ -n "$ROLES" ] || ROLES="controller"
      ;;
    application|app)
      PROFILE_DESCRIPTION="Website/application node with local site database support."
      [ -n "$ROLES" ] || ROLES="web,database"
      ;;
    mail-test)
      PROFILE_DESCRIPTION="Testing-only mail-role baseline ahead of the dedicated mail stack."
      [ -n "$ROLES" ] || ROLES="mail"
      ;;
    dns)
      PROFILE_DESCRIPTION="Tiny DNS-focused node."
      [ -n "$ROLES" ] || ROLES="dns"
      ;;
    backup)
      PROFILE_DESCRIPTION="Backup-target helper baseline for Wasabi-facing backup jobs."
      [ -n "$ROLES" ] || ROLES="backup"
      ;;
    custom)
      [ -n "$ROLES" ] || fail "--profile custom requires --roles"
      PROFILE_DESCRIPTION="Custom role mix."
      ;;
    *)
      fail "Unknown profile: $PROFILE"
      ;;
  esac
}

has_role() {
  printf ',%s,' "$ROLES" | grep -q ",$1,"
}

install_tailscale_repo() {
  local repo_file="/etc/apt/sources.list.d/tailscale.list"
  if [ -f "$repo_file" ]; then
    return 0
  fi

  local codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  [ -n "$codename" ] || fail "Could not determine Ubuntu codename for the Tailscale repository."

  run_cmd "install -d -m 0755 /usr/share/keyrings"
  run_cmd "curl -fsSL 'https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg' -o /usr/share/keyrings/tailscale-archive-keyring.gpg"
  printf 'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu %s main\n' "$codename" >/tmp/aetherpanel-tailscale.list
  run_cmd "install -m 0644 /tmp/aetherpanel-tailscale.list '$repo_file'"
}

install_baseline_packages() {
  local packages=(
    ca-certificates
    certbot
    curl
    fail2ban
    gnupg
    jq
    msmtp-mta
    rsync
    tailscale
  )

  if has_role web || has_role controller; then
    packages+=(
      apache2
      apache2-utils
      php-cli
      php-curl
      php-fpm
      php-mbstring
      php-xml
      php-zip
    )
  fi

  log "Installing baseline packages for profile: $PROFILE"
  run_cmd "apt-get update -y"
  run_cmd "apt-get install -y ca-certificates curl jq gnupg"
  install_tailscale_repo
  run_cmd "apt-get update -y"
  run_cmd "apt-get install -y ${packages[*]}"
}

ensure_operator_user() {
  if ! id "$OPERATOR_USER" >/dev/null 2>&1; then
    run_cmd "useradd -m -s /bin/bash '$OPERATOR_USER'"
  fi
  run_cmd "usermod -aG sudo '$OPERATOR_USER'"
  run_cmd "install -d -m 700 -o '$OPERATOR_USER' -g '$OPERATOR_USER' '/home/$OPERATOR_USER/.ssh'"
  run_cmd "touch '/home/$OPERATOR_USER/.ssh/authorized_keys'"
  run_cmd "chown '$OPERATOR_USER:$OPERATOR_USER' '/home/$OPERATOR_USER/.ssh/authorized_keys'"
  run_cmd "chmod 600 '/home/$OPERATOR_USER/.ssh/authorized_keys'"
  if [ ! -f "/etc/sudoers.d/90-${OPERATOR_USER}" ]; then
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$OPERATOR_USER" >/tmp/aetherpanel-sudoers
    run_cmd "install -m 0440 /tmp/aetherpanel-sudoers '/etc/sudoers.d/90-${OPERATOR_USER}'"
  fi
}

resolve_ssh_pub_source() {
  if [ -n "$SSH_PUB_SOURCE" ] && [ -n "$SSH_PUB_URL" ]; then
    fail "Use either --ssh-pub-source or --ssh-pub-url, not both."
  fi

  if [ -n "$SSH_PUB_SOURCE" ] && [ ! -f "$SSH_PUB_SOURCE" ]; then
    fail "SSH_PUB_SOURCE does not exist: $SSH_PUB_SOURCE"
  fi

  if [ -n "$SSH_PUB_URL" ]; then
    SSH_SOURCE_CACHE="$(mktemp /tmp/aetherpanel-ssh-pubs.XXXXXX)"
    if [ "$DRY_RUN" = "1" ]; then
      printf '[dry-run] curl -fsSL %s -o %s\n' "$SSH_PUB_URL" "$SSH_SOURCE_CACHE"
    else
      curl -fsSL "$SSH_PUB_URL" -o "$SSH_SOURCE_CACHE"
    fi
    SSH_PUB_SOURCE="$SSH_SOURCE_CACHE"
  fi
}

append_authorized_keys() {
  local target="/home/${OPERATOR_USER}/.ssh/authorized_keys"

  if [ -z "$SSH_PUB_SOURCE" ]; then
    log "No SSH public key source provided; skipping public key import"
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    if grep -qxF "$line" "$target"; then
      continue
    fi
    if [ "$DRY_RUN" = "1" ]; then
      printf '[dry-run] append key for %s\n' "$OPERATOR_USER"
    else
      printf '%s\n' "$line" >>"$target"
    fi
  done <"$SSH_PUB_SOURCE"

  run_cmd "chown '$OPERATOR_USER:$OPERATOR_USER' '$target'"
  run_cmd "chmod 600 '$target'"
}

ensure_tailscale() {
  run_cmd "systemctl enable --now tailscaled"
  if tailscale ip -4 >/dev/null 2>&1; then
    return 0
  fi

  if [ -n "$TAILSCALE_AUTHKEY" ]; then
    log "Bringing node onto the tailnet with auth key"
    run_cmd "tailscale up --authkey '$TAILSCALE_AUTHKEY' $TAILSCALE_ARGS"
    return 0
  fi

  log "Launching interactive Tailscale sign-in"
  run_cmd "tailscale up $TAILSCALE_ARGS"
}

configure_fail2ban() {
  cat <<EOF >/tmp/aetherpanel-fail2ban.local
[sshd]
enabled = true
backend = systemd
maxretry = 5
bantime = 1h
findtime = 10m
EOF

  if has_role web || has_role controller; then
    cat <<'EOF' >>/tmp/aetherpanel-fail2ban.local

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/*error.log
maxretry = 6

[apache-badbots]
enabled = true
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 2
EOF
  fi

  run_cmd "install -d -m 0755 /etc/fail2ban/jail.d"
  run_cmd "install -m 0644 /tmp/aetherpanel-fail2ban.local /etc/fail2ban/jail.d/aetherpanel.local"
}

apply_hostname() {
  if [ "$SET_HOSTNAME" != "1" ]; then
    return 0
  fi
  if [ "$(hostname -s)" = "$NODE_NAME" ]; then
    return 0
  fi
  log "Updating host hostname to ${NODE_NAME}"
  run_cmd "hostnamectl set-hostname '$NODE_NAME'"
}

enable_services() {
  run_cmd "systemctl enable --now fail2ban"
  if has_role web || has_role controller; then
    run_cmd "systemctl enable --now apache2"
  fi
}

record_host_facts() {
  local facts_dir="/var/lib/aetherpanel/state"
  local tailscale_ip=""
  local public_ipv4=""
  local private_ipv4=""
  local public_ipv6=""
  local private_ipv6=""

  tailscale_ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  public_ipv4="$(curl -4fsSL --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  private_ipv4="$(ip -4 -o route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || true)"
  public_ipv6="$(curl -6fsSL --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  private_ipv6="$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"

  run_cmd "install -d -m 0755 '$facts_dir'"
  cat <<EOF >/tmp/aetherpanel-host-facts.json
{
  "node_name": "${NODE_NAME}",
  "profile": "${PROFILE}",
  "profile_description": "$(printf '%s' "$PROFILE_DESCRIPTION" | sed 's/"/\\"/g')",
  "roles": "$(printf '%s' "$ROLES")",
  "operator_user": "${OPERATOR_USER}",
  "tailscale_ipv4": "${tailscale_ip}",
  "public_ipv4": "${public_ipv4}",
  "private_ipv4": "${private_ipv4}",
  "public_ipv6": "${public_ipv6}",
  "private_ipv6": "${private_ipv6}"
}
EOF
  run_cmd "install -m 0644 /tmp/aetherpanel-host-facts.json '$facts_dir/host-apply.json'"
}

cleanup() {
  if [ -n "$SSH_SOURCE_CACHE" ] && [ -f "$SSH_SOURCE_CACHE" ]; then
    rm -f "$SSH_SOURCE_CACHE"
  fi
}

print_summary() {
  cat <<EOF

AIetherPanel host baseline applied.

Node:          ${NODE_NAME}
Profile:       ${PROFILE}
Roles:         ${ROLES}
Operator user: ${OPERATOR_USER}
SSH source:    ${SSH_PUB_SOURCE:-not provided}
Security:      fail2ban local, CrowdSec remote-managed

${PROFILE_DESCRIPTION}
EOF
}

main() {
  trap cleanup EXIT
  parse_args "$@"
  require_root
  detect_os
  apply_profile_defaults
  resolve_ssh_pub_source
  install_baseline_packages
  apply_hostname
  ensure_operator_user
  append_authorized_keys
  ensure_tailscale
  configure_fail2ban
  enable_services
  record_host_facts
  print_summary
}

main "$@"
