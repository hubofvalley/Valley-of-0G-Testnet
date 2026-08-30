#!/bin/bash

set -Eeuo pipefail

readonly FALLBACK_CHAIN_ID="16602"
readonly FALLBACK_TARGET_VERSION="v1.4.0"
readonly FALLBACK_TARGET_COMMIT="99c91d95a1d664ffdc9700ef492a00bd76c9c5d1"
readonly KV_REPO="https://github.com/0gfoundation/0g-storage-kv.git"
readonly SERVICE_NAME="zgskv"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
MANIFEST=${VALLEY_MANIFEST_PATH:-}
if [ -z "$MANIFEST" ] && [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../VERSIONS.json" ]; then
    MANIFEST="$SCRIPT_DIR/../VERSIONS.json"
fi

manifest_value() {
    local query=$1 fallback=$2 value=""
    if [ -n "$MANIFEST" ] && [ -f "$MANIFEST" ] && command -v jq >/dev/null 2>&1; then
        value=$(jq -r "$query // empty" "$MANIFEST" 2>/dev/null || true)
    fi
    printf '%s\n' "${value:-$fallback}"
}

EXPECTED_CHAIN_ID=$(manifest_value '.chain.evm_chain_id' "$FALLBACK_CHAIN_ID")
TARGET_VERSION=$(manifest_value '.components.storage_kv.version_current' "$FALLBACK_TARGET_VERSION")
TARGET_COMMIT=$(manifest_value '.components.storage_kv.pinned_commit' "$FALLBACK_TARGET_COMMIT")
KV_DIR=${ZGS_KV_HOME:-$HOME/0g-storage-kv}
CONFIG_FILE=${ZGS_KV_CONFIG_FILE:-$KV_DIR/run/config.toml}
BINARY_FILE="$KV_DIR/target/release/zgs_kv"

if [ -n "${SUDO_USER:-}" ]; then
    echo "Run the updater as the node OS user, not with sudo." >&2
    exit 1
fi

for command_name in curl jq git cargo systemctl; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command is missing: $command_name" >&2
        exit 1
    }
done

canonical_home=$(realpath -m "$HOME")
canonical_kv=$(realpath -m "$KV_DIR")
case "$canonical_kv" in
    "$canonical_home"/*) ;;
    *) echo "Unsafe Storage KV path outside $HOME: $KV_DIR" >&2; exit 1 ;;
esac

if [ ! -d "$KV_DIR" ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "Storage KV or config is missing. Use the installer instead of the updater." >&2
    exit 1
fi

service_file=$(systemctl show "$SERVICE_NAME" -p FragmentPath --value 2>/dev/null || true)
if [ -n "$service_file" ]; then
    if [ ! -f "$service_file" ]; then
        echo "Cannot inspect existing $SERVICE_NAME service file: $service_file" >&2
        exit 1
    fi
    service_exec=$(systemctl cat "$SERVICE_NAME" 2>/dev/null | sed -n 's/^ExecStart=//p' | tail -n 1)
    if [ -n "$service_exec" ] && [[ "$service_exec" != *"$KV_DIR"* ]]; then
        echo "Update blocked: $SERVICE_NAME.service does not appear to belong to $KV_DIR." >&2
        exit 1
    fi
fi

rpc_raw() {
    local endpoint=$1 method=$2
    curl -fsS --connect-timeout 4 --max-time 8 \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" \
        "$endpoint" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || true
}

hex_to_dec() {
    local value=$1
    if [[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf '%d\n' "$((16#${value#0x}))"
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
    fi
}

inspect_rpc() {
    local endpoint=$1 chain_hex chain_dec block_hex block_dec
    chain_hex=$(rpc_raw "$endpoint" eth_chainId)
    chain_dec=$(hex_to_dec "$chain_hex")
    if [ "$chain_dec" != "$EXPECTED_CHAIN_ID" ]; then
        printf 'REJECTED chain=%s expected=%s\n' "${chain_dec:-unavailable}" "$EXPECTED_CHAIN_ID"
        return 1
    fi
    block_hex=$(rpc_raw "$endpoint" eth_blockNumber)
    block_dec=$(hex_to_dec "$block_hex")
    printf 'OK chain=%s block=%s\n' "$chain_dec" "${block_dec:-unavailable}"
}

require_rpc() {
    local endpoint=$1 rpc_status
    if ! rpc_status=$(inspect_rpc "$endpoint"); then
        echo "RPC rejected: $endpoint ($rpc_status)" >&2
        return 1
    fi
    echo "RPC verified: $endpoint ($rpc_status)"
}

choose_json_rpc_endpoint() {
    local choice public_choice continue_choice
    while true; do
        echo "Choose your JSON-RPC endpoint:"
        echo "1. Enter your own JSON-RPC endpoint"
        echo "2. Use a public JSON-RPC endpoint"
        read -r -p "Enter your choice (1/2): " choice
        case "$choice" in
            1)
                read -r -p "Enter your JSON-RPC endpoint: " BLOCKCHAIN_RPC_ENDPOINT
                if require_rpc "$BLOCKCHAIN_RPC_ENDPOINT"; then
                    read -r -p "Do you want to continue with this RPC endpoint? (yes/no): " continue_choice
                    [ "$continue_choice" = "yes" ] && return 0
                fi
                ;;
            2)
                echo "Available public JSON-RPC endpoints (chain ID is verified before use):"
                echo "1. https://lightnode-json-rpc-0g.grandvalleys.com [$(inspect_rpc https://lightnode-json-rpc-0g.grandvalleys.com 2>/dev/null || true)]"
                echo "2. https://evmrpc-testnet.0g.ai [$(inspect_rpc https://evmrpc-testnet.0g.ai 2>/dev/null || true)]"
                read -r -p "Enter the number of your chosen public JSON-RPC endpoint: " public_choice
                case "$public_choice" in
                    1) BLOCKCHAIN_RPC_ENDPOINT="https://lightnode-json-rpc-0g.grandvalleys.com" ;;
                    2) BLOCKCHAIN_RPC_ENDPOINT="https://evmrpc-testnet.0g.ai" ;;
                    *) echo "Invalid choice."; continue ;;
                esac
                require_rpc "$BLOCKCHAIN_RPC_ENDPOINT" && return 0
                ;;
            *) echo "Invalid choice." ;;
        esac
    done
}

read -r -p "Enter storage node URLs (e.g., http://STORAGE_NODE_IP:5678,http://STORAGE_NODE_IP:5679): " ZGS_NODE
[ -n "$ZGS_NODE" ] || { echo "Storage node URLs cannot be empty." >&2; exit 1; }
choose_json_rpc_endpoint

echo
echo "Storage KV update plan"
echo "- Network chain ID: $EXPECTED_CHAIN_ID"
echo "- Managed target: $TARGET_VERSION ($TARGET_COMMIT)"
echo "- Existing database: preserved; updater will not delete run/db"
echo "- Build/download work: completed before service downtime"
echo "- Rollback: previous binary and config are backed up before swap"
echo

tmpdir=$(mktemp -d)
backup_dir="$KV_DIR/run/valley-backups/$(date -u +%Y%m%dT%H%M%SZ)"
candidate_config="$tmpdir/config.toml"
staged_binary="$tmpdir/0g-storage-kv/target/release/zgs_kv"
rollback_ready=0
service_stopped=0
success=0

rollback() {
    [ "$rollback_ready" -eq 1 ] || return 0
    echo "Update failed after downtime began; restoring the previous Storage KV binary/config." >&2
    sudo cp "$backup_dir/zgs_kv" "$BINARY_FILE" 2>/dev/null || true
    sudo cp "$backup_dir/config.toml" "$CONFIG_FILE" 2>/dev/null || true
    sudo systemctl restart "$SERVICE_NAME" 2>/dev/null || true
}

cleanup() {
    local rc=$?
    if [ "$success" -ne 1 ] && [ "$service_stopped" -eq 1 ]; then
        rollback
    fi
    rm -rf "$tmpdir"
    return "$rc"
}
trap cleanup EXIT

echo "Preparing target while $SERVICE_NAME remains online..."
git clone --quiet "$KV_REPO" "$tmpdir/0g-storage-kv"
git -C "$tmpdir/0g-storage-kv" checkout --quiet --detach "$TARGET_COMMIT"
git -C "$tmpdir/0g-storage-kv" submodule update --init --recursive
if [ "$(git -C "$tmpdir/0g-storage-kv" rev-parse HEAD)" != "$TARGET_COMMIT" ]; then
    echo "Unexpected Storage KV source commit after checkout." >&2
    exit 1
fi
(cd "$tmpdir/0g-storage-kv" && cargo build --release)
[ -x "$staged_binary" ] || { echo "Staged zgs_kv binary was not produced." >&2; exit 1; }

cp "$CONFIG_FILE" "$candidate_config"
sed -i -E \
    -e "s|^[[:space:]]*blockchain_rpc_endpoint[[:space:]]*=.*|blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"|" \
    -e "s|^[[:space:]]*zgs_node_urls[[:space:]]*=.*|zgs_node_urls = \"$ZGS_NODE\"|" \
    "$candidate_config"
grep -Fq "blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"" "$candidate_config" || {
    echo "Failed to stage blockchain_rpc_endpoint without rebuilding config." >&2
    exit 1
}
grep -Fq "zgs_node_urls = \"$ZGS_NODE\"" "$candidate_config" || {
    echo "Failed to stage zgs_node_urls without rebuilding config." >&2
    exit 1
}

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
[ -f "$BINARY_FILE" ] || { echo "Current zgs_kv binary is missing at $BINARY_FILE." >&2; exit 1; }
cp "$BINARY_FILE" "$backup_dir/zgs_kv"
cp "$CONFIG_FILE" "$backup_dir/config.toml"
chmod 600 "$backup_dir/config.toml"
rollback_ready=1

install -m 0755 "$staged_binary" "$BINARY_FILE.valley-new"
install -m 0600 "$candidate_config" "$CONFIG_FILE.valley-new"

echo "Preflight complete. Starting short downtime window..."
sudo systemctl stop "$SERVICE_NAME"
service_stopped=1
mv -f "$BINARY_FILE.valley-new" "$BINARY_FILE"
mv -f "$CONFIG_FILE.valley-new" "$CONFIG_FILE"
sudo systemctl restart "$SERVICE_NAME"
sleep 2

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "$SERVICE_NAME did not become active after the update." >&2
    exit 1
fi

success=1
service_stopped=0
echo "Storage KV update completed successfully with managed target $TARGET_VERSION."
echo "Database was preserved. Backup retained at: $backup_dir"
