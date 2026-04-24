# lib/postgres.sh — install PostgreSQL from the PGDG repo with small-VPS tuning.
# shellcheck shell=bash

# Conservative, battle-tested defaults for a 1-4 GB VPS. Override via pg_conf
# snippets if you know what you're doing.
_vi_pg_tuning() {
  cat <<'EOF'
# Managed by vps-init. Override with another file that loads later via:
#   include_dir = '/etc/postgresql/<ver>/main/conf.d'
listen_addresses = 'localhost'
max_connections = 50
shared_buffers = 256MB
effective_cache_size = 768MB
maintenance_work_mem = 64MB
work_mem = 4MB
min_wal_size = 80MB
max_wal_size = 1GB
checkpoint_completion_target = 0.9
wal_buffers = 7864kB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
log_min_duration_statement = 500ms
timezone = 'Asia/Shanghai'
EOF
}

# HBA rules: local socket uses peer auth; localhost TCP uses scram-sha-256.
# We do NOT open to 0.0.0.0 — use an SSH tunnel or a proper bastion for remote.
_vi_pg_hba() {
  cat <<'EOF'
# Managed by vps-init.
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
EOF
}

vi_cmd_postgres() {
  vi_detect_distro
  if [[ "$VI_DISTRO" == "unsupported" ]]; then
    vi_err "unsupported distribution"
    return 1
  fi

  local version="16"
  local create_user="" create_db=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)     version="$2"; shift 2 ;;
      --version=*)   version="${1#--version=}"; shift ;;
      --create-user) create_user="$2"; shift 2 ;;
      --create-db)   create_db="$2"; shift 2 ;;
      *) vi_warn "unknown flag: $1"; shift ;;
    esac
  done

  vi_step "PostgreSQL $version"

  # Install from PGDG (the Postgres-official repo). The distro-packaged Postgres
  # on Debian/Ubuntu is usable but often lags current minor by 6-12 months.
  if ! dpkg -s "postgresql-$version" >/dev/null 2>&1; then
    vi_apt_install ca-certificates curl gnupg

    vi_run install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/pgdg.gpg ]]; then
      vi_run bash -c "curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/pgdg.gpg"
      vi_run chmod a+r /etc/apt/keyrings/pgdg.gpg
    fi

    local repo="deb [signed-by=/etc/apt/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt $VI_CODENAME-pgdg main"
    vi_install_file /etc/apt/sources.list.d/pgdg.list "$repo" 0644

    vi_run apt-get update
    vi_apt_install "postgresql-$version" "postgresql-contrib-$version"
  else
    vi_info "postgresql-$version already installed"
  fi

  local conf_dir="/etc/postgresql/$version/main"
  local data_dir="/var/lib/postgresql/$version/main"

  if [[ ! -d "$conf_dir" ]]; then
    vi_err "config directory not found after install: $conf_dir"
    return 1
  fi

  # Write tuned settings into conf.d so the main postgresql.conf stays stock.
  vi_run install -d -m 0755 "$conf_dir/conf.d"
  vi_install_file "$conf_dir/conf.d/10-vps-init.conf" "$(_vi_pg_tuning)" 0644

  # Ensure include_dir is active.
  if ! grep -qE "^[[:space:]]*include_dir[[:space:]]*=" "$conf_dir/postgresql.conf"; then
    vi_backup_file "$conf_dir/postgresql.conf"
    echo "include_dir = 'conf.d'" >> "$conf_dir/postgresql.conf"
    vi_info "enabled include_dir = 'conf.d' in postgresql.conf"
  fi

  # Install HBA (back up first).
  vi_install_file "$conf_dir/pg_hba.conf" "$(_vi_pg_hba)" 0640
  vi_run chown postgres:postgres "$conf_dir/pg_hba.conf"

  # Ensure service is running and enabled.
  vi_run systemctl enable --now "postgresql@$version-main"
  vi_run systemctl reload "postgresql@$version-main"

  # Optional: create a role + database for your app, with a random generated
  # password written to /root/.pg-<user>-password (0600). We DON'T echo the
  # password to stdout — the operator should cat the file.
  if [[ -n "$create_user" ]]; then
    if sudo -u postgres psql -tAc "select 1 from pg_roles where rolname='$create_user'" | grep -q 1; then
      vi_info "role '$create_user' already exists"
    else
      local pw
      pw=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
      sudo -u postgres psql -c "CREATE ROLE \"$create_user\" LOGIN PASSWORD '$pw';" >/dev/null
      local pwfile="/root/.pg-$create_user-password"
      umask 077
      printf '%s\n' "$pw" > "$pwfile"
      chmod 0600 "$pwfile"
      vi_ok "created role '$create_user' — password written to $pwfile"
    fi
  fi

  if [[ -n "$create_db" ]]; then
    if sudo -u postgres psql -tAc "select 1 from pg_database where datname='$create_db'" | grep -q 1; then
      vi_info "database '$create_db' already exists"
    else
      local owner_clause=""
      [[ -n "$create_user" ]] && owner_clause="OWNER \"$create_user\""
      sudo -u postgres psql -c "CREATE DATABASE \"$create_db\" $owner_clause ENCODING 'UTF8' LC_COLLATE='C.UTF-8' LC_CTYPE='C.UTF-8' TEMPLATE=template0;" >/dev/null
      vi_ok "created database '$create_db'"
    fi
  fi

  # Sanity probe.
  if sudo -u postgres psql -tAc 'select version()' >/dev/null 2>&1; then
    local ver
    ver=$(sudo -u postgres psql -tAc 'select version()' | awk '{print $2}')
    vi_ok "postgres running: $ver"
  else
    vi_err "postgres service is not responding. check: journalctl -u postgresql@$version-main"
    return 1
  fi
}
