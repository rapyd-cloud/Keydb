#!/bin/bash
set -euo pipefail

# Configuration
readonly DYNAMIC_MEM_CONF_FILE="/etc/keydb/maxmemory.conf"
readonly DEFAULT_PERCENTAGE=10
readonly FALLBACK_MEM_MB=512
CACHE_MEM_LIMIT_MB=${FALLBACK_MEM_MB}

echo "--- KeyDB Memory Configuration ---"

if [ -f /etc/jelastic/metainf.conf ] && grep -q CACHE_MEM_LIMIT /etc/jelastic/metainf.conf; then
    LIMIT_FROM_FILE=$(grep CACHE_MEM_LIMIT /etc/jelastic/metainf.conf | cut -d'=' -f2)
    if [[ -n "$LIMIT_FROM_FILE" && "$LIMIT_FROM_FILE" -gt 0 ]]; then
        echo "Found CACHE_MEM_LIMIT in environment: ${LIMIT_FROM_FILE}MB"
        CACHE_MEM_LIMIT_MB=$LIMIT_FROM_FILE
    else
        echo "CACHE_MEM_LIMIT found but invalid. Using fallback: ${FALLBACK_MEM_MB}MB"
    fi
else
    echo "CACHE_MEM_LIMIT not found. Using fallback: ${FALLBACK_MEM_MB}MB"
fi

MAX_MEMORY_BYTES=$((CACHE_MEM_LIMIT_MB * 1024 * 1024 * DEFAULT_PERCENTAGE / 100))

echo "Setting maxmemory to ${DEFAULT_PERCENTAGE}% of ${CACHE_MEM_LIMIT_MB}MB -> ${MAX_MEMORY_BYTES} bytes."
echo "maxmemory ${MAX_MEMORY_BYTES}" > "${DYNAMIC_MEM_CONF_FILE}"
chown keydb:keydb "${DYNAMIC_MEM_CONF_FILE}"
chmod 644 "${DYNAMIC_MEM_CONF_FILE}"

echo "✅ KeyDB maxmemory set successfully."
exit 0
