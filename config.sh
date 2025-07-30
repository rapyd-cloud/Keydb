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
readonly PHP_CONF_DIR="/usr/local/lsws/lsphp/etc/php.d"
readonly KEYDB_SESSION_CONF_FILE="${PHP_CONF_DIR}/90-keydb-session.ini"
readonly SESSION_DB=0
readonly USER_NAME="keydb"
readonly GROUP_NAME="litespeed"
readonly RUN_DIR="/run/redis"

# --- Pre-flight Checks ---
if [[ "$EUID" -ne 0 ]]; then die "This script must be run as root."; fi
REQUIRED_CMDS=("systemctl" "chown" "chmod" "mkdir" "rm" "getent" "usermod" "sed" "curl")
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command_exists "$cmd"; then die "Required command '$cmd' not found."; fi
done

# --- Use the full keydb.conf as a base ---
echo "Copying and configuring the main keydb.conf..."
# Assuming keydb.conf.txt is in the same directory as the script during execution
# If not, this path needs to be adjusted.
SCRIPT_DIR=$(dirname "$0")
cp "${SCRIPT_DIR}/keydb.conf.txt" "${KEYDB_CONF_FILE}"

# --- Apply necessary configurations ---
sed -i 's/^supervised no/supervised systemd/' "${KEYDB_CONF_FILE}"
sed -i 's/^#port 6379/port 0/' "${KEYDB_CONF_FILE}"
sed -i 's/^unixsocketperm 777/unixsocketperm 770/' "${KEYDB_CONF_FILE}"
sed -i 's|^logfile /var/log/keydb/keydb-server.log|logfile /var/log/keydb/keydb.log|' "${KEYDB_CONF_FILE}"
echo "include ${MAXMEMORY_CONF_FILE}" >> "${KEYDB_CONF_FILE}"

chown "${USER_NAME}:${USER_NAME}" "${KEYDB_CONF_FILE}"
chmod 644 "${KEYDB_CONF_FILE}"

# --- Create a default maxmemory.conf file BEFORE service start ---
echo "Creating default maxmemory.conf..."
echo "maxmemory 512mb" > "${MAXMEMORY_CONF_FILE}"
chown "${USER_NAME}:${USER_NAME}" "${MAXMEMORY_CONF_FILE}"
chmod 644 "${MAXMEMORY_CONF_FILE}"

# --- Create Secure systemd Service File ---
echo "Creating secure redis.service file..."
cat <<EOF > "${REDIS_SERVICE_FILE}"
[Unit]
Description=Advanced key-value store
After=network.target
Documentation=https://docs.keydb.dev, man:keydb-server(1)

[Service]
Type=notify
User=keydb
Group=keydb
ExecStart=/usr/bin/keydb-server /etc/keydb/keydb.conf --supervised systemd --server-threads 2
ExecStop=/bin/kill -s TERM \$MAINPID
PIDFile=/run/redis/redis.pid
TimeoutStopSec=0
Restart=always
RuntimeDirectory=redis
RuntimeDirectoryMode=0755

UMask=007
PrivateTmp=yes
LimitNOFILE=65535
PrivateDevices=yes
ProtectHome=yes
ReadOnlyDirectories=/
ReadWriteDirectories=-/var/lib/keydb
ReadWriteDirectories=-/var/log/keydb
ReadWriteDirectories=-/var/run/keydb

NoNewPrivileges=true
CapabilityBoundingSet=CAP_SETGID CAP_SETUID CAP_SYS_RESOURCE
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

ProtectSystem=true
ReadWriteDirectories=-/etc/keydb

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
systemctl daemon-reload
systemctl enable --now redis
systemctl restart redis

echo "KeyDB configuration completed successfully."
exit 0
