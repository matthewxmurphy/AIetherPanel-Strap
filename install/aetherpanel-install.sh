#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
export NEEDRESTART_MODE="${NEEDRESTART_MODE:-a}"

AETHERPANEL_VERSION="0.1.2"
PROFILE="hybrid"
NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
ROLES=""
CONTROLLER_URL=""
CONTROLLER_API_URL=""
PUBLIC_HOSTNAME=""
PANEL_USER="aetherpanel"
PANEL_GROUP="www-data"
PANEL_PORT="8844"
PANEL_ROOT="/opt/aetherpanel"
PANEL_ETC="/etc/aetherpanel"
PANEL_VAR="/var/lib/aetherpanel"
PANEL_LOG="/var/log/aetherpanel"
PANEL_APP="${PANEL_ROOT}/ui"
PANEL_WWW="${PANEL_APP}/public"
LIGHTTPD_TEMPLATE=""
LIGHTTPD_SERVICE_TEMPLATE=""
PANEL_UI_SOURCE=""
TAILSCALE_IP=""
ADMIN_USER=""
ADMIN_PASSWORD=""
DRY_RUN="0"
PHP_FPM_SOCKET=""
INSTALL_SOURCE_ROOT="${AETHERPANEL_INSTALL_SOURCE_ROOT:-https://raw.githubusercontent.com/matthewxmurphy/AetherPanel-Strap/main}"
AETHERPANEL_SOURCE_DIR=""
STEP_CACHE_DIR=""
PROFILE_DESCRIPTION=""
OPERATOR_USER="mmurphy"
SSH_PUB_SOURCE=""
SSH_PUB_URL=""
TAILSCALE_AUTHKEY=""
TAILSCALE_ARGS=""
SET_HOSTNAME="0"
SSH_SOURCE_CACHE=""
JOIN_KEY=""
CONTROL_DB_ENABLED="0"
CONTROL_DB_DRIVER="mysql"
CONTROL_DB_HOST=""
CONTROL_DB_PORT=""
CONTROL_DB_DATABASE=""
CONTROL_DB_USERNAME=""
CONTROL_DB_PASSWORD=""
CONTROL_DB_SSL_MODE="preferred"
CONTROL_DB_CA_PATH=""

usage() {
  cat <<'EOF'
AetherPanel installer

Usage:
  aetherpanel-install.sh [options]

Options:
  --profile hybrid|controller|application|app|mail-test|dns|backup|custom
  --node-name NAME
  --roles controller,web,database
  --controller-url URL
  --controller-api-url URL
  --control-panel-api-url URL
  --join-key KEY
  --reg-key KEY
  --public-hostname HOSTNAME
  --panel-port PORT
  --admin-user USER
  --admin-password PASSWORD
  --operator-user USER
  --control-db-enabled
  --control-db-driver mysql|mariadb|pgsql
  --control-db-host HOST
  --control-db-port PORT
  --control-db-database NAME
  --control-db-username USER
  --control-db-password PASSWORD
  --control-db-ssl-mode MODE
  --control-db-ca-path /path/to/ca.pem
  --ssh-pub-source /path/to/public-keys.txt
  --ssh-pub-url URL
  --tailscale-authkey KEY
  --tailscale-args "..."
  --set-hostname
  --install-source-root URL
  --dry-run
  -h, --help

Notes:
  - The per-server panel is bound to the Tailscale IPv4 by default.
  - Apache stays available for websites. AetherPanel lighttpd runs as its own dedicated service.
  - If MariaDB/Postgres is installed here, that is for websites, not panel state.
  - Fail2ban is local. CrowdSec is handled remotely and is not installed by this script.
  - This single script is the normal node bootstrap path.
  - The separate host-apply script is only for later re-apply/repair.
  - If no panel login user is provided, the installer uses the operator user and generates a temporary password.
  - If the controller API, join key, or external control database are not ready yet, omit those flags for now.
  - Use controller for a dedicated controller node, application for a website/application host,
    mail-test for the future testing mail node, and hybrid for the current all-in-one baseline.
EOF
}

log() {
  printf '[aetherpanel] %s\n' "$*"
}

fail() {
  printf '[aetherpanel] ERROR: %s\n' "$*" >&2
  exit 1
}

run_cmd() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  eval "$@"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "Run this installer as root."
  fi
}

detect_os() {
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ]; then
    fail "Ubuntu is required for the first AetherPanel host baseline."
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --profile)
        PROFILE="${2:-}"; shift 2 ;;
      --node-name)
        NODE_NAME="${2:-}"; shift 2 ;;
      --roles)
        ROLES="${2:-}"; shift 2 ;;
      --controller-url)
        CONTROLLER_URL="${2:-}"; shift 2 ;;
      --controller-api-url)
        CONTROLLER_API_URL="${2:-}"; shift 2 ;;
      --control-panel-api-url)
        CONTROLLER_API_URL="${2:-}"; shift 2 ;;
      --join-key)
        JOIN_KEY="${2:-}"; shift 2 ;;
      --reg-key)
        JOIN_KEY="${2:-}"; shift 2 ;;
      --public-hostname)
        PUBLIC_HOSTNAME="${2:-}"; shift 2 ;;
      --panel-port)
        PANEL_PORT="${2:-}"; shift 2 ;;
      --admin-user)
        ADMIN_USER="${2:-}"; shift 2 ;;
      --admin-password)
        ADMIN_PASSWORD="${2:-}"; shift 2 ;;
      --operator-user)
        OPERATOR_USER="${2:-}"; shift 2 ;;
      --control-db-enabled)
        CONTROL_DB_ENABLED="1"; shift ;;
      --control-db-driver)
        CONTROL_DB_DRIVER="${2:-}"; shift 2 ;;
      --control-db-host)
        CONTROL_DB_HOST="${2:-}"; shift 2 ;;
      --control-db-port)
        CONTROL_DB_PORT="${2:-}"; shift 2 ;;
      --control-db-database)
        CONTROL_DB_DATABASE="${2:-}"; shift 2 ;;
      --control-db-username)
        CONTROL_DB_USERNAME="${2:-}"; shift 2 ;;
      --control-db-password)
        CONTROL_DB_PASSWORD="${2:-}"; shift 2 ;;
      --control-db-ssl-mode)
        CONTROL_DB_SSL_MODE="${2:-}"; shift 2 ;;
      --control-db-ca-path)
        CONTROL_DB_CA_PATH="${2:-}"; shift 2 ;;
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
      --install-source-root)
        INSTALL_SOURCE_ROOT="${2:-}"; shift 2 ;;
      --dry-run)
        DRY_RUN="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        fail "Unknown option: $1" ;;
    esac
  done
}

apply_profile_defaults() {
  case "$PROFILE" in
    hybrid)
      PROFILE_DESCRIPTION="Hybrid controller/app/database baseline for the current OCI production pair."
      [ -n "$ROLES" ] || ROLES="controller,web,database"
      ;;
    controller)
      PROFILE_DESCRIPTION="Dedicated controller node with the per-server panel and fleet/operator baseline."
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

normalize_login_defaults() {
  if [ -z "$ADMIN_USER" ]; then
    ADMIN_USER="$OPERATOR_USER"
  fi

  if [ -z "$ADMIN_USER" ]; then
    ADMIN_USER="admin"
  fi
}

has_role() {
  printf ',%s,' "$ROLES" | grep -q ",$1,"
}

apply_hostname() {
  if [ "$SET_HOSTNAME" != "1" ]; then
    return 0
  fi
  if [ "$(hostname -s 2>/dev/null || hostname)" = "$NODE_NAME" ]; then
    return 0
  fi
  log "Updating host hostname to ${NODE_NAME}"
  run_cmd "hostnamectl set-hostname '$NODE_NAME'"
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

detect_tailscale_ip() {
  if command -v tailscale >/dev/null 2>&1; then
    TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  fi
  if [ -z "$TAILSCALE_IP" ]; then
    TAILSCALE_IP="$(ip -4 -o addr show tailscale0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"
  fi
  if [ -z "$TAILSCALE_IP" ]; then
    fail "No Tailscale IPv4 detected. Bring Tailscale up before binding the panel on this server."
  fi
}

validate_control_db_config() {
  case "$CONTROL_DB_DRIVER" in
    mysql|mariadb|pgsql) ;;
    *)
      fail "Unsupported control database driver: $CONTROL_DB_DRIVER"
      ;;
  esac

  if [ -z "$CONTROL_DB_PORT" ]; then
    if [ "$CONTROL_DB_DRIVER" = "pgsql" ]; then
      CONTROL_DB_PORT="5432"
    else
      CONTROL_DB_PORT="3306"
    fi
  fi

  if ! printf '%s' "$CONTROL_DB_PORT" | grep -Eq '^[0-9]{2,5}$'; then
    fail "Control database port must be numeric."
  fi

  if [ "$CONTROL_DB_ENABLED" = "1" ]; then
    [ -n "$CONTROL_DB_HOST" ] || fail "--control-db-host is required when the control database lane is enabled."
    [ -n "$CONTROL_DB_DATABASE" ] || fail "--control-db-database is required when the control database lane is enabled."
    [ -n "$CONTROL_DB_USERNAME" ] || fail "--control-db-username is required when the control database lane is enabled."
  fi
}

resolve_source_dir() {
  local source_ref="${BASH_SOURCE[0]:-$0}"
  if [ -n "$source_ref" ] && [ -e "$source_ref" ]; then
    local script_dir
    script_dir="$(cd "$(dirname "$source_ref")" && pwd)"
    if [ -d "$script_dir/../ui" ] && [ -d "$script_dir/../conf" ]; then
      AETHERPANEL_SOURCE_DIR="$(cd "$script_dir/.." && pwd)"
    fi
  fi
}

stage_support_file() {
  local relative="$1"
  local destination="$2"
  if [ -n "$AETHERPANEL_SOURCE_DIR" ] && [ -f "$AETHERPANEL_SOURCE_DIR/$relative" ]; then
    run_cmd "install -m 0644 '$AETHERPANEL_SOURCE_DIR/$relative' '$destination'"
    return 0
  fi

  run_cmd "curl -fsSL '${INSTALL_SOURCE_ROOT%/}/$relative' -o '$destination'"
}

stage_support_tree() {
  [ -n "$STEP_CACHE_DIR" ] || STEP_CACHE_DIR="$(mktemp -d /tmp/aetherpanel-install.XXXXXX)"
  PANEL_UI_SOURCE="$STEP_CACHE_DIR/ui"
  LIGHTTPD_TEMPLATE="$STEP_CACHE_DIR/lighttpd-aetherpanel.conf.template"
  LIGHTTPD_SERVICE_TEMPLATE="$STEP_CACHE_DIR/aetherpanel-lighttpd.service.template"

  run_cmd "install -d -m 0755 '$PANEL_UI_SOURCE/lib' '$PANEL_UI_SOURCE/public/assets'"
  stage_support_file "conf/lighttpd-aetherpanel.conf.template" "$LIGHTTPD_TEMPLATE"
  stage_support_file "conf/aetherpanel-lighttpd.service.template" "$LIGHTTPD_SERVICE_TEMPLATE"
  stage_support_file "ui/lib/bootstrap.php" "$PANEL_UI_SOURCE/lib/bootstrap.php"
  stage_support_file "ui/public/index.php" "$PANEL_UI_SOURCE/public/index.php"
  stage_support_file "ui/public/assets/aetherpanel.css" "$PANEL_UI_SOURCE/public/assets/aetherpanel.css"
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

install_packages() {
  local packages=(
    apache2-utils
    ca-certificates
    certbot
    curl
    fail2ban
    gnupg
    jq
    lighttpd
    msmtp-mta
    php-cli
    php-curl
    php-fpm
    php-mysql
    php-pgsql
    php-mbstring
    php-xml
    php-zip
    tailscale
  )

  if has_role web; then
    packages+=(apache2)
  fi

  log "Installing host baseline packages"
  run_cmd "apt-get update -y"
  run_cmd "apt-get install -y ca-certificates curl jq gnupg"
  if command -v debconf-set-selections >/dev/null 2>&1; then
    printf 'msmtp msmtp/apparmor boolean false\n' >/tmp/aetherpanel-debconf.seed
    run_cmd "debconf-set-selections /tmp/aetherpanel-debconf.seed"
  fi
  install_tailscale_repo
  run_cmd "apt-get update -y"
  run_cmd "apt-get install -y -o Dpkg::Use-Pty=0 ${packages[*]}"
}

ensure_user_group() {
  getent group "$PANEL_GROUP" >/dev/null 2>&1 || fail "Required runtime group missing: $PANEL_GROUP"
  id "$PANEL_USER" >/dev/null 2>&1 || run_cmd "useradd --system --gid $PANEL_GROUP --home $PANEL_VAR --shell /usr/sbin/nologin $PANEL_USER"
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

ensure_dirs() {
  run_cmd "install -d -m 0750 -o $PANEL_USER -g $PANEL_GROUP $PANEL_ROOT $PANEL_ETC $PANEL_APP"
  run_cmd "install -d -m 0770 -o $PANEL_USER -g $PANEL_GROUP $PANEL_VAR $PANEL_VAR/state $PANEL_LOG"
  run_cmd "install -d -m 0755 -o $PANEL_USER -g $PANEL_GROUP $PANEL_WWW"
}

write_node_env() {
  cat <<EOF >/tmp/aetherpanel-node.env
AETHERPANEL_VERSION=${AETHERPANEL_VERSION}
PROFILE=${PROFILE}
NODE_NAME=${NODE_NAME}
ROLES=${ROLES}
OPERATOR_USER=${OPERATOR_USER}
CONTROLLER_URL=${CONTROLLER_URL}
CONTROLLER_API_URL=${CONTROLLER_API_URL}
JOIN_KEY=${JOIN_KEY}
PUBLIC_HOSTNAME=${PUBLIC_HOSTNAME}
TAILSCALE_IP=${TAILSCALE_IP}
PANEL_PORT=${PANEL_PORT}
PANEL_ROOT=${PANEL_ROOT}
PANEL_ETC=${PANEL_ETC}
PANEL_VAR=${PANEL_VAR}
PANEL_LOG=${PANEL_LOG}
EOF
  run_cmd "install -m 0640 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-node.env $PANEL_ETC/node.env"
}

write_join_seed() {
  local join_mode="pending-license"
  if [ -n "$JOIN_KEY" ]; then
    join_mode="join"
  elif [ -n "$CONTROLLER_URL" ] || [ -n "$CONTROLLER_API_URL" ]; then
    join_mode="controller-known"
  fi

  cat <<EOF >/tmp/aetherpanel-join.json
{
  "controller_url": "${CONTROLLER_URL}",
  "controller_api_url": "${CONTROLLER_API_URL}",
  "join_mode": "${join_mode}",
  "join_key_present": $([ -n "$JOIN_KEY" ] && printf 'true' || printf 'false'),
  "profile": "${PROFILE}",
  "roles": "$(printf '%s' "$ROLES")"
}
EOF
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-join.json $PANEL_VAR/state/join.json"
}

write_branding_seed() {
  cat <<EOF >/tmp/aetherpanel-branding.json
{
  "project_name": "AetherPanel",
  "business_end": "AI Control Host",
  "owner": "Matthew Murphy",
  "organization_name": "Net30 Hosting",
  "support_url": "https://www.net30hosting.com/support",
  "ecommerce_url": "https://www.net30hosting.com",
  "billing_url": "https://billing.net30hosting.com",
  "create_account_url": "https://www.net30hosting.com",
  "logout_destination_url": "https://www.net30hosting.com",
  "system_email_from": "hello@net30hosting.com",
  "logo_light": "",
  "logo_dark": "",
  "logo_compact": "",
  "favicon": "",
  "inverse_icon": "",
  "compact_mark_text": "N30",
  "login_page_image": "",
  "public_domains": [
    "www.matthewxmurphy.com",
    "www.net30hosting.com"
  ],
  "brand_color": "#F8931F",
  "secondary_color": "#111111",
  "font_family": "Noto Sans",
  "border_radius": 18,
  "default_dark_mode": true
}
EOF
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-branding.json $PANEL_VAR/state/branding.json"
}

write_control_db_seed() {
  local enabled_json="false"
  local driver="$CONTROL_DB_DRIVER"
  local host=""
  local port=""
  local database=""
  local username=""
  local password=""
  local ssl_mode=""
  local ca_path=""

  [ "$CONTROL_DB_ENABLED" = "1" ] && enabled_json="true"
  if [ "$CONTROL_DB_ENABLED" = "1" ]; then
    host="$CONTROL_DB_HOST"
    port="$CONTROL_DB_PORT"
    database="$CONTROL_DB_DATABASE"
    username="$CONTROL_DB_USERNAME"
    password="$CONTROL_DB_PASSWORD"
    ssl_mode="$CONTROL_DB_SSL_MODE"
    ca_path="$CONTROL_DB_CA_PATH"
  fi

  jq -n \
    --argjson enabled "$enabled_json" \
    --arg driver "$driver" \
    --arg host "$host" \
    --arg port "$port" \
    --arg database "$database" \
    --arg username "$username" \
    --arg password "$password" \
    --arg ssl_mode "$ssl_mode" \
    --arg ca_path "$ca_path" \
    '{
      enabled: $enabled,
      driver: $driver,
      host: $host,
      port: $port,
      database: $database,
      username: $username,
      password: $password,
      ssl_mode: $ssl_mode,
      ca_path: $ca_path
    }' >/tmp/aetherpanel-control-db.json
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-control-db.json $PANEL_VAR/state/control-db.json"
}

write_control_db_env_seed() {
  if [ "$CONTROL_DB_ENABLED" != "1" ]; then
    cat <<'EOF' >/tmp/aetherpanel-controller-db.env
# External control database is still pending on this server.
# Save and test the real managed database details from the AetherPanel UI when they exist.
EOF
    run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-controller-db.env $PANEL_VAR/state/controller-db.env"
    return 0
  fi

  {
    printf 'DB_CONNECTION=%s\n' "$CONTROL_DB_DRIVER"
    printf 'DB_HOST=%s\n' "$CONTROL_DB_HOST"
    printf 'DB_PORT=%s\n' "$CONTROL_DB_PORT"
    printf 'DB_DATABASE=%s\n' "$CONTROL_DB_DATABASE"
    printf 'DB_USERNAME=%s\n' "$CONTROL_DB_USERNAME"
    printf 'DB_PASSWORD=%s\n' "$CONTROL_DB_PASSWORD"
    if [ "$CONTROL_DB_DRIVER" = "pgsql" ]; then
      printf 'DB_SSLMODE=%s\n' "$CONTROL_DB_SSL_MODE"
    elif [ -n "$CONTROL_DB_CA_PATH" ]; then
      printf 'MYSQL_ATTR_SSL_CA=%s\n' "$CONTROL_DB_CA_PATH"
    fi
  } >/tmp/aetherpanel-controller-db.env
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-controller-db.env $PANEL_VAR/state/controller-db.env"
}

write_onboarding_seed() {
  cat <<'EOF' >/tmp/aetherpanel-onboarding.json
{
  "title": "Your account setup",
  "subtitle": "Finish the first fleet steps before handing real websites and customers to AetherPanel.",
  "ssh_known_ip_lock": false,
  "control_database_ready": false,
  "backup_target_ready": false,
  "hosting_package_ready": false,
  "import_ready": false,
  "items": [
    {
      "id": "register_controller_identity",
      "title": "Register controller identity",
      "summary": "When the control API is live, attach this server to the controller identity and redeem its join/license key."
    },
    {
      "id": "add_first_node",
      "title": "Add first node",
      "summary": "Track the first hybrid controller/app/database node in fleet inventory."
    },
    {
      "id": "confirm_tailscale_bind",
      "title": "Confirm Tailscale bind",
      "summary": "Keep the panel on this server reachable only over the tailnet."
    },
    {
      "id": "lock_ssh_to_known_ips",
      "title": "Lock SSH to known IPs",
      "summary": "Restrict port 22 to Tailscale and approved known IP lanes."
    },
    {
      "id": "set_default_web_stack",
      "title": "Set default web stack",
      "summary": "Use Apache, PHP 8.5, website-local database access, Let’s Encrypt, msmtp, jailed SFTP, and Sequel Ace-friendly operator access as the baseline."
    },
    {
      "id": "connect_control_database",
      "title": "Connect control database",
      "summary": "When the free control database exists, point panel state, sessions, cache, jobs, and fleet inventory at it."
    },
    {
      "id": "set_backup_target",
      "title": "Set backup target",
      "summary": "Point backups at Wasabi and verify restore posture."
    },
    {
      "id": "add_first_role_user",
      "title": "Add first role user",
      "summary": "Create the first operator beyond the bootstrap admin account."
    },
    {
      "id": "add_first_hosting_package",
      "title": "Add first hosting package",
      "summary": "Create the default package for shared and dedicated site placement."
    },
    {
      "id": "import_existing_sites",
      "title": "Import existing sites",
      "summary": "Bring current website inventory and external panel state into AetherPanel."
    }
  ]
}
EOF
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-onboarding.json $PANEL_VAR/state/onboarding.json"
}

write_panel_model_seed() {
  cat <<EOF >/tmp/aetherpanel-users.toon
title: "AetherPanel Users"
roles:
  - id: "platform_admin"
    label: "Platform Admin"
    description: "Full control of branding, roles, nodes, migrations, and firewall policy."
  - id: "fleet_operator"
    label: "Fleet Operator"
    description: "Can manage nodes, vhosts, certificates, packages, and migrations."
  - id: "web_operator"
    label: "Web Operator"
    description: "Can manage sites, PHP packages, SFTP users, and certificates."
  - id: "mail_operator"
    label: "Mail Operator"
    description: "Can manage outbound mail posture and mail-role migrations."
  - id: "dns_operator"
    label: "DNS Operator"
    description: "Can manage DNS-role assignments and DNS-related moves."
  - id: "billing_viewer"
    label: "Billing Viewer"
    description: "Read-only access to bandwidth, disk, and cost summaries."
users:
  - username: "${ADMIN_USER}"
    roles:
      - "platform_admin"
EOF
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-users.toon $PANEL_VAR/state/users.toon"
  cat <<EOF >/tmp/aetherpanel-users.json
{
  "roles": [
    {
      "id": "platform_admin",
      "label": "Platform Admin",
      "description": "Full control of branding, roles, nodes, migrations, and firewall posture.",
      "permissions": [
        "edit branding",
        "manage users",
        "manage roles",
        "manage nodes",
        "manage firewall posture",
        "approve migrations",
        "view billing summaries"
      ]
    },
    {
      "id": "fleet_operator",
      "label": "Fleet Operator",
      "description": "Can manage nodes, vhosts, certificates, and migrations.",
      "permissions": [
        "manage nodes",
        "manage vhosts",
        "apply certificates",
        "start migrations"
      ]
    },
    {
      "id": "web_operator",
      "label": "Web Operator",
      "description": "Can manage sites, PHP packages, and jailed SFTP users.",
      "permissions": [
        "create vhosts",
        "edit php packages",
        "manage jailed sftp users",
        "view vhost telemetry",
        "manage database connection profiles"
      ]
    },
    {
      "id": "mail_operator",
      "label": "Mail Operator",
      "description": "Can manage outbound mail posture and mail-role changes.",
      "permissions": [
        "manage outbound mail posture",
        "move mail role",
        "view mail host assignments"
      ]
    },
    {
      "id": "dns_operator",
      "label": "DNS Operator",
      "description": "Can manage DNS role placement and DNS changes.",
      "permissions": [
        "manage dns role assignments",
        "move dns role",
        "view dns host assignments"
      ]
    },
    {
      "id": "billing_viewer",
      "label": "Billing Viewer",
      "description": "Read-only access to disk, bandwidth, and billing summaries.",
      "permissions": [
        "view disk summaries",
        "view bandwidth summaries",
        "view billing summaries"
      ]
    }
  ],
  "users": [
    {
      "username": "${ADMIN_USER}",
      "display_name": "Bootstrap Admin",
      "roles": ["platform_admin"]
    }
  ]
}
EOF
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-users.json $PANEL_VAR/state/users.json"
}

write_basic_auth() {
  local auth_file="${PANEL_ETC}/users.htpasswd"

  if [ -f "$auth_file" ] && grep -q "^${ADMIN_USER}:" "$auth_file" && [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="<unchanged>"
    chown "$PANEL_USER:$PANEL_GROUP" "$auth_file" || true
    chmod 0660 "$auth_file" || true
    return 0
  fi

  if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -d '\n' | cut -c1-24)"
  fi
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] htpasswd -iBc %s/users.htpasswd %s\n' "$PANEL_ETC" "$ADMIN_USER"
    return 0
  fi
  if [ -f "$auth_file" ]; then
    printf '%s\n' "$ADMIN_PASSWORD" | htpasswd -iB "$auth_file" "$ADMIN_USER"
  else
    printf '%s\n' "$ADMIN_PASSWORD" | htpasswd -iBc "$auth_file" "$ADMIN_USER"
  fi
  chown "$PANEL_USER:$PANEL_GROUP" "$auth_file"
  chmod 0660 "$auth_file"
}

detect_php_fpm_socket() {
  PHP_FPM_SOCKET="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' 2>/dev/null | sort | head -n1 || true)"
  if [ -z "$PHP_FPM_SOCKET" ]; then
    fail "No php-fpm socket found under /run/php."
  fi
}

ensure_php_fpm_running() {
  local services
  services="$(systemctl list-unit-files 'php*-fpm.service' --no-legend 2>/dev/null | awk '{print $1}' || true)"
  if [ -z "$services" ]; then
    fail "No php-fpm systemd service found after package install."
  fi

  while IFS= read -r service; do
    [ -n "$service" ] || continue
    run_cmd "systemctl enable --now '$service'"
  done <<EOF
$services
EOF
}

ensure_tailscale_connected() {
  run_cmd "systemctl enable --now tailscaled"
  if tailscale ip -4 >/dev/null 2>&1; then
    return 0
  fi

  if [ -n "$TAILSCALE_AUTHKEY" ]; then
    log "Bringing node onto the tailnet with auth key"
    run_cmd "tailscale up --authkey '$TAILSCALE_AUTHKEY' $TAILSCALE_ARGS"
    return 0
  fi

  log "Launching Tailscale sign-in or sign-up flow"
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

  if has_role web; then
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

sync_ui_tree() {
  run_cmd "rm -rf '$PANEL_APP'"
  run_cmd "install -d -m 0750 -o $PANEL_USER -g $PANEL_GROUP '$PANEL_APP'"
  run_cmd "cp -R '$PANEL_UI_SOURCE'/. '$PANEL_APP'/"
  run_cmd "chown -R $PANEL_USER:$PANEL_GROUP '$PANEL_APP'"
  run_cmd "find '$PANEL_APP' -type d -exec chmod 0750 {} +"
  run_cmd "find '$PANEL_APP' -type f -exec chmod 0640 {} +"
  run_cmd "chmod 0750 '$PANEL_WWW'"
  run_cmd "find '$PANEL_WWW' -type f -exec chmod 0644 {} +"
  run_cmd "find '$PANEL_WWW' -type d -exec chmod 0755 {} +"
}

write_lighttpd_config() {
  sed \
    -e "s|__DOCROOT__|$PANEL_WWW|g" \
    -e "s|__PORT__|$PANEL_PORT|g" \
    -e "s|__BIND_IP__|$TAILSCALE_IP|g" \
    -e "s|__LOGDIR__|$PANEL_LOG|g" \
    -e "s|__ETC__|$PANEL_ETC|g" \
    -e "s|__NODE_NAME__|$NODE_NAME|g" \
    -e "s|__PHP_FPM_SOCKET__|$PHP_FPM_SOCKET|g" \
    -e "s|__PANEL_USER__|$PANEL_USER|g" \
    -e "s|__PANEL_GROUP__|$PANEL_GROUP|g" \
    -e "s|__PANEL_VAR__|$PANEL_VAR|g" \
    "$LIGHTTPD_TEMPLATE" >/tmp/aetherpanel-lighttpd.conf
  run_cmd "install -m 0644 /tmp/aetherpanel-lighttpd.conf '$PANEL_ETC/lighttpd.conf'"

  sed \
    -e "s|__LIGHTTPD_BIN__|$(command -v lighttpd)|g" \
    -e "s|__CONFIG__|$PANEL_ETC/lighttpd.conf|g" \
    "$LIGHTTPD_SERVICE_TEMPLATE" >/tmp/aetherpanel-lighttpd.service
  run_cmd "install -m 0644 /tmp/aetherpanel-lighttpd.service /etc/systemd/system/aetherpanel-lighttpd.service"
  run_cmd "lighttpd -tt -f '$PANEL_ETC/lighttpd.conf'"
}

enable_apache_php_baseline() {
  local php_apache_conf=""

  if ! has_role web; then
    return 0
  fi

  php_apache_conf="$(find /etc/apache2/conf-available -maxdepth 1 -name 'php*-fpm.conf' 2>/dev/null | xargs -n1 basename 2>/dev/null | head -n1 | sed 's/\.conf$//' || true)"

  run_cmd "a2enmod proxy_fcgi setenvif ssl rewrite"
  if [ -n "$php_apache_conf" ]; then
    run_cmd "a2enconf '$php_apache_conf'"
  fi
  run_cmd "apache2ctl configtest"
}

enable_services() {
  run_cmd "systemctl disable --now lighttpd || true"
  run_cmd "systemctl daemon-reload"
  run_cmd "systemctl enable --now aetherpanel-lighttpd"
  if has_role web; then
    enable_apache_php_baseline
    run_cmd "systemctl enable --now apache2"
  fi
  run_cmd "systemctl enable --now fail2ban"
}

record_host_facts() {
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

  cat <<EOF >/tmp/aetherpanel-host-facts.json
{
  "node_name": "${NODE_NAME}",
  "profile": "${PROFILE}",
  "roles": "$(printf '%s' "$ROLES")",
  "operator_user": "${OPERATOR_USER}",
  "tailscale_ipv4": "${tailscale_ip}",
  "public_ipv4": "${public_ipv4}",
  "private_ipv4": "${private_ipv4}",
  "public_ipv6": "${public_ipv6}",
  "private_ipv6": "${private_ipv6}"
}
EOF
  run_cmd "install -m 0660 -o $PANEL_USER -g $PANEL_GROUP /tmp/aetherpanel-host-facts.json '$PANEL_VAR/state/host-facts.json'"
}

cleanup() {
  if [ -n "$SSH_SOURCE_CACHE" ] && [ -f "$SSH_SOURCE_CACHE" ]; then
    rm -f "$SSH_SOURCE_CACHE"
  fi
}

source_step_script() {
  local step_file="$1"
  local step_path=""

  if [ -n "$AETHERPANEL_SOURCE_DIR" ] && [ -f "$AETHERPANEL_SOURCE_DIR/install/steps/$step_file" ]; then
    step_path="$AETHERPANEL_SOURCE_DIR/install/steps/$step_file"
  else
    [ -n "$STEP_CACHE_DIR" ] || STEP_CACHE_DIR="$(mktemp -d /tmp/aetherpanel-install.XXXXXX)"
    step_path="$STEP_CACHE_DIR/$step_file"
    run_cmd "curl -fsSL '${INSTALL_SOURCE_ROOT%/}/install/steps/$step_file' -o '$step_path'"
  fi

  # shellcheck source=/dev/null
  . "$step_path"
}

load_step_scripts() {
  resolve_source_dir
  source_step_script "10-preflight.sh"
  source_step_script "20-packages.sh"
  source_step_script "30-tailscale.sh"
  source_step_script "40-panel-files.sh"
  source_step_script "50-services.sh"
}

print_summary() {
  local controller_label="${CONTROLLER_URL:-Pending until the control API is ready}"
  local controller_api_label="${CONTROLLER_API_URL:-Pending until the control API is ready}"
  local join_mode_label="pending-license"

  if [ -n "$JOIN_KEY" ]; then
    join_mode_label="join"
  elif [ -n "$CONTROLLER_URL" ] || [ -n "$CONTROLLER_API_URL" ]; then
    join_mode_label="controller-known"
  fi

  cat <<EOF

AetherPanel bootstrap complete.

Node:          ${NODE_NAME}
Profile:       ${PROFILE}
Roles:         ${ROLES}
Tailnet bind:  http://${TAILSCALE_IP}:${PANEL_PORT}
Controller:    ${controller_label}
Controller API:${controller_api_label}
Join mode:     ${join_mode_label}
Admin user:    ${ADMIN_USER}
Admin pass:    ${ADMIN_PASSWORD}

Branding seed:  ${PANEL_VAR}/state/branding.json
Control DB:     ${PANEL_VAR}/state/control-db.json
Control DB env: ${PANEL_VAR}/state/controller-db.env
Role seed:      ${PANEL_VAR}/state/users.toon
Node config:    ${PANEL_ETC}/node.env

Remember:
- lighttpd is the dedicated per-server AetherPanel service on this host
- Apache only installs when the profile carries the web role
- Fail2ban is local. CrowdSec stays remote-managed.
- host MariaDB/Postgres is for websites, not panel state

${PROFILE_DESCRIPTION}
EOF
}

main() {
  trap cleanup EXIT
  parse_args "$@"
  apply_profile_defaults
  normalize_login_defaults
  validate_control_db_config
  load_step_scripts
  aetherpanel_step_preflight
  aetherpanel_step_packages
  aetherpanel_step_tailscale
  aetherpanel_step_panel_files
  aetherpanel_step_services
  print_summary
}

main "$@"
