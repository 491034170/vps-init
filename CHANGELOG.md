# Changelog

## [0.1.3] — database modules

### Added
- `postgres` module — installs PostgreSQL from the official PGDG APT repo
  (not the distro-packaged one, which lags). Drops a tuned
  `conf.d/10-vps-init.conf` with small-VPS defaults (`shared_buffers=256M`,
  `effective_cache_size=768M`, aggressive `work_mem` sizing, `wal` ratios,
  `Asia/Shanghai` tz). `pg_hba` locks auth to `peer` (local socket) and
  `scram-sha-256` (localhost TCP) — nothing listens on the public IP.
  Optional `--create-user <name>` generates a random password and writes
  it to `/root/.pg-<name>-password` (0600). `--create-db <name>` creates
  a UTF-8 database owned by the created user.
- `mysql` module — MySQL 8 from the distro (or `--mariadb` to install
  MariaDB instead). Tuned `conf.d/10-vps-init.cnf` with
  `innodb_buffer_pool_size=256M`, `bind-address=127.0.0.1`, `utf8mb4`
  defaults. Runs the standard "remove anonymous users / test db / remote
  root" hardening steps idempotently. Same `--create-user`/`--create-db`
  flow as the postgres module.
- New built-in profile `saas-pg` — `web-cn` + Node + PostgreSQL. The
  common shape for a single-box SaaS MVP.

### Notes
- Both DB modules default to small-VPS tuning; drop your own
  `/etc/<pg|mysql>/conf.d/99-your-overrides.conf` with higher numeric
  prefix to win.
- Neither module opens DB ports to the public internet. Use an SSH
  tunnel (`ssh -L 5432:localhost:5432 vps`) for remote access.

## [0.1.2] — workflow release

### Added
- `apply <profile>` accepts `--only a,b,c` and `--skip x,y` filters so you
  can re-run a subset of a profile against a server that's already
  partially configured. `--only` validates each name against the profile
  and fails loudly on a typo (previously a typo would have silently
  skipped everything). `--skip` is more lenient — unknown names warn
  but don't abort. The two flags are mutually exclusive.
- End-of-run summary now reports how many modules ran vs. skipped.

## [0.1.1] — minor feature release

### Added
- `user <name>` module — create an operator user with sudo access and SSH
  keys in one command. Key sources, in priority order:
  `--key-file <path>`, `--copy-key-from <existing-user>`,
  `--github <gh-login>` (fetches from `github.com/<login>.keys`).
  Sudoers is managed as a per-user file in `/etc/sudoers.d/90-<name>`
  validated with `visudo -cf` before the drop-in is committed.
  `--sudo-nopasswd` available.
- `install.sh` — `curl | sudo bash` installer matching `site-bootstrap`.

### Changed
- `list` now includes the `user` module with its flags.
- README roadmap now checks off the `user` item.

## [0.1.0] — initial public release

### Added
- `apply <profile>` profile runner with 4 built-in profiles:
  - `minimal` — timezone + mirror + base (no-web) + swap.
  - `web-cn` — full web VPS in China/HK with nginx + certbot + firewall + fail2ban + hardened SSH.
  - `node-app` — `web-cn` + Node via nvm + pnpm + pm2.
  - `docker-host` — Docker CE host with firewall/SSH hardening.
- Standalone modules, all idempotent:
  - `mirror` — swap apt sources (aliyun / tuna / ustc / 163 / huaweicloud).
  - `base` — opinionated base package set; nginx + certbot optional via `--no-web`.
  - `swap` — swap file with tuned `vm.swappiness=10` / `vm.vfs_cache_pressure=50`.
  - `timezone` — default `Asia/Shanghai`, enables `systemd-timesyncd`.
  - `firewall` — UFW with auto-detected SSH port + 80/443.
  - `fail2ban` — tuned sshd jail with escalating bantime.
  - `ssh-hardening` — key-only, with a safety check that refuses to lock you
    out if no `authorized_keys` exists anywhere.
  - `node` — nvm + pnpm + pm2 for the invoking user.
  - `docker` — Docker CE from Docker's official repo + signing key.
  - `doctor` — human-readable state summary.
- Both legacy `sources.list` and Ubuntu 24.04+ deb822 `ubuntu.sources` formats
  are handled correctly.
- Every config-editing operation creates a timestamped backup on first change.

### Design
- Every module is safe to re-run. Idempotency is enforced by content
  comparisons (`vi_install_file`) and state probes (`ufw status`, `dpkg -s`,
  `/proc/swaps`, etc.), not by markers.
- `--dry-run` prints what would happen without executing.
- SSH hardening guards against the classic "I locked myself out" foot-gun.
