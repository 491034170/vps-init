# lib/mysql.sh — install MySQL 8 (or MariaDB fallback) with small-VPS tuning.
# shellcheck shell=bash

# Tuning geared at 1-4 GB VPS, single-app workloads. Aggressive memory limits
# to avoid the OOM killer eating mysqld on memory pressure.
_vi_mysql_tuning() {
  cat <<'EOF'
# Managed by vps-init — small-VPS tuning. Drop your own overrides into another
# file in /etc/mysql/conf.d/ with a higher numeric prefix to win.
[mysqld]
bind-address            = 127.0.0.1
character-set-server    = utf8mb4
collation-server        = utf8mb4_0900_ai_ci
default_authentication_plugin = caching_sha2_password

innodb_buffer_pool_size = 256M
innodb_log_file_size    = 128M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method     = O_DIRECT

max_connections         = 50
thread_cache_size       = 16
table_open_cache        = 400

slow_query_log          = 1
slow_query_log_file     = /var/log/mysql/mysql-slow.log
long_query_time         = 1

# UTC at storage; display-layer should convert.
default_time_zone       = '+00:00'
EOF
}

vi_cmd_mysql() {
  vi_detect_distro
  if [[ "$VI_DISTRO" == "unsupported" ]]; then
    vi_err "unsupported distribution"
    return 1
  fi

  local flavor="mysql"  # mysql | mariadb
  local create_user="" create_db=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mariadb)     flavor="mariadb"; shift ;;
      --create-user) create_user="$2"; shift 2 ;;
      --create-db)   create_db="$2"; shift 2 ;;
      *) vi_warn "unknown flag: $1"; shift ;;
    esac
  done

  if [[ "$flavor" == "mariadb" ]]; then
    vi_step "MariaDB"
    vi_apt_install mariadb-server
  else
    vi_step "MySQL 8"
    # Debian Bookworm (12) has MySQL 8 in main. Ubuntu Jammy (22.04) has 8.0.
    # For Noble (24.04) default-mysql-server is also 8. Distro package is fine
    # for most cases; operators who need the latest minor can add the
    # MySQL-Official APT repo themselves.
    if ! dpkg -s mysql-server >/dev/null 2>&1 && ! dpkg -s default-mysql-server >/dev/null 2>&1; then
      if apt-cache show mysql-server >/dev/null 2>&1; then
        vi_apt_install mysql-server
      else
        vi_apt_install default-mysql-server
      fi
    else
      vi_info "mysql-server already installed"
    fi
  fi

  # Install the vps-init tuning snippet.
  local conf_dir="/etc/mysql/conf.d"
  [[ "$flavor" == "mariadb" ]] && conf_dir="/etc/mysql/mariadb.conf.d"
  vi_run install -d -m 0755 "$conf_dir"
  vi_install_file "$conf_dir/10-vps-init.cnf" "$(_vi_mysql_tuning)" 0644

  local svc="mysql"
  [[ "$flavor" == "mariadb" ]] && svc="mariadb"
  vi_run systemctl enable --now "$svc"
  vi_run systemctl restart "$svc"

  # Harden: remove anonymous users, test db, remote root. Idempotent.
  local sql
  sql=$(cat <<'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
SQL
)
  if [[ "${VI_DRY_RUN:-0}" != "1" ]]; then
    printf '%s\n' "$sql" | mysql --defaults-group-suffix= 2>/dev/null || \
      printf '%s\n' "$sql" | sudo mysql || \
      vi_warn "basic hardening SQL failed — run 'mysql_secure_installation' manually"
  fi

  # Optional user + db creation.
  if [[ -n "$create_user" ]]; then
    local pw
    pw=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
    local pwfile="/root/.mysql-$create_user-password"
    local sql2
    sql2="CREATE USER IF NOT EXISTS '$create_user'@'localhost' IDENTIFIED BY '$pw'; "
    [[ -n "$create_db" ]] && sql2+="CREATE DATABASE IF NOT EXISTS \`$create_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci; GRANT ALL PRIVILEGES ON \`$create_db\`.* TO '$create_user'@'localhost'; "
    sql2+="FLUSH PRIVILEGES;"

    if [[ "${VI_DRY_RUN:-0}" == "1" ]]; then
      vi_info "(dry-run) would create user '$create_user' and (maybe) db '$create_db'"
    else
      if sudo mysql -e "$sql2" 2>/dev/null; then
        umask 077
        printf '%s\n' "$pw" > "$pwfile"
        chmod 0600 "$pwfile"
        vi_ok "created user '$create_user' — password written to $pwfile"
        [[ -n "$create_db" ]] && vi_ok "created database '$create_db' (owner $create_user)"
      else
        vi_err "failed to create user/db. check mysql service and socket auth."
        return 1
      fi
    fi
  elif [[ -n "$create_db" ]]; then
    # db without user — create anonymously, warn that no one can use it
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$create_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;" 2>/dev/null \
      && vi_ok "created database '$create_db' (no user granted — pass --create-user to create one)"
  fi

  # Sanity probe.
  if sudo mysql -e 'SELECT VERSION()' >/dev/null 2>&1; then
    local ver
    ver=$(sudo mysql -Ne 'SELECT VERSION()')
    vi_ok "$flavor running: $ver"
  else
    vi_warn "service started but socket auth failed. Try: sudo mysql"
  fi
}
