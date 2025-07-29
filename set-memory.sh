#!/bin/bash
set -euo pipefail

# Configuration
readonly DYNAMIC_MEM_CONF_FILE="/etc/keydb/maxmemory.conf"
readonly DEFAULT_PERCENTAGE=10 # Set to 10% as requested
CACHE_MEM_LIMIT_MB=512 # Fallback value if not found

if [ -f /etc/jelastic/metainf.conf ]; then
    LIMIT_FROM_FILE=$(grep CACHE_MEM_LIMIT /etc/jelastic/metainf.conf | cut -d'=' -f2)
    if [[ -n "$LIMIT_FROM_FILE" ]]; then
        CACHE_MEM_LIMIT_MB=$LIMIT_FROM_FILE
    fi
fi

# Calculate memory in bytes
MAX_MEMORY_BYTES=$((CACHE_MEM_LIMIT_MB * 1024 * 1024 * DEFAULT_PERCENTAGE / 100))

# Write the configuration
echo "maxmemory ${MAX_MEMORY_BYTES}" > "${DYNAMIC_MEM_CONF_FILE}"
chown keydb:keydb "${DYNAMIC_MEM_CONF_FILE}"
chmod 644 "${DYNAMIC_MEM_CONF_FILE}"

echo "✅ KeyDB maxmemory set to ${MAX_MEMORY_BYTES} bytes."
exit 0