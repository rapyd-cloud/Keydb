#!/bin/bash
set -euo pipefail

# Helper functions
die() { echo "ERROR: $1" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Configuration paths
readonly KEYDB_CONF_DIR="/etc/keydb"
readonly SYSTEMD_SYS_DIR="/usr/lib/systemd/system"
readonly REDIS_SERVICE_FILE="${SYSTEMD_SYS_DIR}/redis.service"
readonly PHP_CONF_DIR="/usr/local/lsws/lsphp/etc/php.d"
readonly KEYDB_SESSION_CONF_FILE="${PHP_CONF_DIR}/90-keydb-session.ini"
readonly SESSION_DB=0
readonly USER_NAME="keydb"
readonly GROUP_NAME="litespeed"

# Pre-flight Checks
if [[ "$EUID" -ne 0 ]]; then die "This script must be run as root."; fi
REQUIRED_CMDS=("systemctl" "chown" "chmod" "mkdir" "rm" "getent" "usermod")
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command_exists "$cmd"; then die "Required command '$cmd' not found."; fi
done

# Check if keydb.conf exists
[[ -f "${KEYDB_CONF_DIR}/keydb.conf" ]] || die "Missing keydb.conf in ${KEYDB_CONF_DIR}"

# Create redis.service if missing
if [[ ! -f "${REDIS_SERVICE_FILE}" ]]; then
  echo "Creating redis.service file..."
  cat <<EOF > "${REDIS_SERVICE_FILE}"
[Unit]
Description=KeyDB (Redis-compatible mode)
After=network.target

[Service]
User=keydb
Group=keydb
ExecStart=/usr/bin/keydb-server /etc/keydb/keydb.conf --server-threads 2
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=always
LimitNOFILE=10032

[Install]
WantedBy=multi-user.target
EOF
fi

# Create necessary directories
mkdir -p /var/run/redis /var/lib/keydb /var/log/keydb
chown -R "${USER_NAME}:${USER_NAME}" /var/run/redis /var/lib/keydb /var/log/keydb
chmod 755 /var/run/redis /var/lib/keydb /var/log/keydb

# Configure PHP Sessions
mkdir -p "${PHP_CONF_DIR}"
cat << EOF > "${KEYDB_SESSION_CONF_FILE}"
session.save_handler = redis
session.save_path = "unix:///var/run/redis/redis.sock?database=${SESSION_DB}"
EOF

# Add keydb user to litespeed group (if it exists)
if getent group "${GROUP_NAME}" &>/dev/null; then
  usermod -a -G "${GROUP_NAME}" "${USER_NAME}"
fi

# Reload and enable systemd service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable redis

echo "✅ KeyDB configuration completed successfully."
exit 0
