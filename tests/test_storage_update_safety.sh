#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STORAGE_UPDATE="$ROOT/resources/0g_storage_node_update.sh"
KV_UPDATE="$ROOT/resources/0g_storage_kv_update.sh"
STORAGE_CHANGE="$ROOT/resources/0g_storage_node_change.sh"

fail() { echo "STORAGE_UPDATE_SAFETY_TEST_FAIL: $*" >&2; exit 1; }

for file in "$STORAGE_UPDATE" "$KV_UPDATE"; do
    grep -Fq 'eth_chainId' "$file" || fail "missing eth_chainId guard in $file"
    grep -Fq 'valley-backups' "$file" || fail "missing recovery-point backup in $file"
    grep -Fq 'rollback' "$file" || fail "missing rollback path in $file"
    if grep -Eq 'echo[^#\n]*PRIVATE_KEY|read[^#\n]*PRIVATE_KEY' "$file"; then
        fail "updater must not request or print a private key: $file"
    fi
    build_line=$(grep -n 'cargo build --release' "$file" | head -n1 | cut -d: -f1)
    stop_line=$(grep -n 'systemctl stop' "$file" | tail -n1 | cut -d: -f1)
    [ -n "$build_line" ] && [ -n "$stop_line" ] || fail "could not prove build/stop ordering in $file"
    [ "$build_line" -lt "$stop_line" ] || fail "service stops before target build completes in $file"
done

if grep -Eq 'rm[[:space:]].*run/db' "$KV_UPDATE"; then
    fail "Storage KV updater must preserve run/db"
fi
grep -Fq 'listen_address_admin = "127.0.0.1:5679"' "$STORAGE_CHANGE" || fail "storage admin RPC must default to loopback"

echo "STORAGE_UPDATE_SAFETY_TEST_OK"
