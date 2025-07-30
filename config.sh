#!/bin/bash
set -euo pipefail

# Helper functions
die() { echo "ERROR: $1" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- Configuration paths ---
readonly KEYDB_CONF_DIR="/etc/keydb"
readonly KEYDB_CONF_FILE="${KEYDB_CONF_DIR}/keydb.conf"
readonly MAXMEMORY_CONF_FILE="${KEYDB_CONF_DIR}/maxmemory.conf"
readonly SYSTEMD_SYS_DIR="/usr/lib/systemd/system"
readonly REDIS_SERVICE_FILE="${SYSTEMD_SYS_DIR}/redis.service"
readonly DEFAULT_KEYDB_SERVICE_FILE="${SYSTEMD_SYS_DIR}/keydb.service"
readonly PHP_CONF_DIR="/usr/local/lsws/lsphp/etc/php.d"
readonly KEYDB_SESSION_CONF_FILE="${PHP_CONF_DIR}/90-keydb-session.ini"
readonly SESSION_DB=0
readonly USER_NAME="keydb"
readonly GROUP_NAME="litespeed"
readonly RUN_DIR="/run/redis"

# --- Pre-flight Checks ---
if [[ "$EUID" -ne 0 ]]; then die "This script must be run as root."; fi
for cmd in systemctl chown chmod mkdir rm getent usermod sed; do
  if ! command_exists "$cmd"; then die "Required command '$cmd' not found."; fi
done

# --- Use the full keydb.conf as a base ---
echo "Copying and configuring the main keydb.conf from /root/keydb.conf.txt..."
if [ ! -f /root/keydb.conf.txt ]; then
    die "Configuration file /root/keydb.conf.txt not found. It should have been downloaded by the manifest."
fi
cp "/root/keydb.conf.txt" "${KEYDB_CONF_FILE}"

# --- Apply necessary configurations ---
sed -i 's/^daemonize yes/daemonize no/' "${KEYDB_CONF_FILE}"
sed -i 's/^supervised no/supervised systemd/' "${KEYDB_CONF_FILE}"
sed -i 's/^#port 6379/port 0/' "${KEYDB_CONF_FILE}"
sed -i "s|^pidfile .*|pidfile ${RUN_DIR}/redis.pid|" "${KEYDB_CONF_FILE}"
sed -i "s|^unixsocket .*|unixsocket ${RUN_DIR}/redis.sock|" "${KEYDB_CONF_FILE}"
sed -i 's/^unixsocketperm 777/unixsocketperm 770/' "${KEYDB_CONF_FILE}"
sed -i 's|^logfile .*|logfile /var/log/keydb/keydb.log|' "${KEYDB_CONF_FILE}"
sed -i 's|^dir .*|dir /var/lib/keydb|' "${KEYDB_CONF_FILE}"
# Add the include directive if it's not already there
grep -qF "include ${MAXMEMORY_CONF_FILE}" "${KEYDB_CONF_FILE}" || echo "include ${MAXMEMORY_CONF_FILE}" >> "${KEYDB_CONF_FILE}"

chown "${USER_NAME}:${USER_NAME}" "${KEYDB_CONF_FILE}"
chmod 644 "${KEYDB_CONF_FILE}"

# --- Create a default maxmemory.conf file ---
echo "Creating default maxmemory.conf..."
echo "maxmemory 512mb" > "${MAXMEMORY_CONF_FILE}"
chown "${USER_NAME}:${USER_NAME}" "${MAXMEMORY_CONF_FILE}"
chmod 644 "${MAXMEMORY_CONF_FILE}"

# --- Create Secure systemd Service File (as redis.service) ---
echo "Creating secure redis.service file at ${REDIS_SERVICE_FILE}..."
cat <<EOF > "${REDIS_SERVICE_FILE}"
[Unit]
Description=KeyDB (Redis-compatible mode)
After=network.target
Documentation=https://docs.keydb.dev

[Service]
Type=notify
User=keydb
Group=keydb
ExecStart=/usr/bin/keydb-server ${KEYDB_CONF_FILE} --supervised systemd --server-threads 2
ExecStop=/bin/kill -s TERM \$MAINPID
PIDFile=${RUN_DIR}/redis.pid
Restart=always
LimitNOFILE=65535
RuntimeDirectory=redis
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
Alias=keydb.service
EOF

# --- Create Directories ---
mkdir -p "${RUN_DIR}" /var/lib/keydb /var/log/keydb
chown -R "${USER_NAME}:${USER_NAME}" "${RUN_DIR}" /var/lib/keydb /var/log/keydb
chmod 755 "${RUN_DIR}" /var/lib/keydb /var/log/keydb

# --- Configure PHP Sessions ---
mkdir -p "${PHP_CONF_DIR}"
cat << EOF > "${KEYDB_SESSION_CONF_FILE}"
session.save_handler = redis
session.save_path = "unix://${RUN_DIR}/redis.sock?database=${SESSION_DB}"
EOF

# --- Add keydb user to litespeed group ---
if getent group "${GROUP_NAME}" &>/dev/null; then
  usermod -a -G "${GROUP_NAME}" "${USER_NAME}"
fi

# --- Reload and Enable Service ---
echo "Reloading systemd and enabling the service..."
systemctl daemon-reload
systemctl enable --now redis.service

echo "KeyDB configuration completed successfully."
exit 0
