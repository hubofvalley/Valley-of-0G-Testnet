#!/bin/bash

set -Eeuo pipefail

readonly EXPECTED_EVM_CHAIN_ID="16602"
readonly SERVICE_NAME="zgs"
readonly CONFIG_FILE="${ZGS_CONFIG_FILE:-$HOME/0g-storage-node/run/config-testnet.toml}"

rpc_result() {
    local endpoint=$1 method=$2
    curl -fsS --connect-timeout 4 --max-time 8 -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" 2>/dev/null |
        jq -r '.result // empty' 2>/dev/null || true
}

hex_to_dec() {
    local value=$1
    if [[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]; then printf '%d\n' "$((16#${value#0x}))";
    elif [[ "$value" =~ ^[0-9]+$ ]]; then printf '%s\n' "$value"; fi
}

require_rpc_chain() {
    local endpoint=$1 chain_raw chain_id block_raw block_id
    chain_raw=$(rpc_result "$endpoint" eth_chainId)
    chain_id=$(hex_to_dec "$chain_raw")
    if [ "$chain_id" != "$EXPECTED_EVM_CHAIN_ID" ]; then
        echo "RPC rejected: $endpoint reports chain ${chain_id:-unavailable}; expected $EXPECTED_EVM_CHAIN_ID." >&2
        return 1
    fi
    block_raw=$(rpc_result "$endpoint" eth_blockNumber)
    block_id=$(hex_to_dec "$block_raw")
    echo "RPC verified: chain=$chain_id block=${block_id:-unavailable}"
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
                if require_rpc_chain "$BLOCKCHAIN_RPC_ENDPOINT"; then
                    read -r -p "Do you want to continue with this RPC endpoint? (yes/no): " continue_choice
                    [ "$continue_choice" = "yes" ] && return 0
                fi
                ;;
            2)
                echo "Available public JSON-RPC endpoints (verified before use):"
                echo "1. https://lightnode-json-rpc-0g.grandvalleys.com"
                echo "2. https://evmrpc-testnet.0g.ai"
                read -r -p "Enter the number of your chosen public JSON-RPC endpoint: " public_choice
                case "$public_choice" in
                    1) BLOCKCHAIN_RPC_ENDPOINT="https://lightnode-json-rpc-0g.grandvalleys.com" ;;
                    2) BLOCKCHAIN_RPC_ENDPOINT="https://evmrpc-testnet.0g.ai" ;;
                    *) echo "Invalid choice."; continue ;;
                esac
                require_rpc_chain "$BLOCKCHAIN_RPC_ENDPOINT" && return 0
                ;;
            *) echo "Invalid choice." ;;
        esac
    done
}

[ -f "$CONFIG_FILE" ] || { echo "Storage config not found: $CONFIG_FILE" >&2; exit 1; }

service_file=$(systemctl show "$SERVICE_NAME" -p FragmentPath --value 2>/dev/null || true)
if [ -n "$service_file" ]; then
    [ -f "$service_file" ] || { echo "Cannot inspect $SERVICE_NAME service: $service_file" >&2; exit 1; }
    service_exec=$(systemctl cat "$SERVICE_NAME" 2>/dev/null | sed -n 's/^ExecStart=//p' | tail -n 1)
    if [ -n "$service_exec" ] && [[ "$service_exec" != *"$HOME/0g-storage-node"* ]]; then
        echo "Change blocked: $SERVICE_NAME.service belongs to another instance." >&2
        exit 1
    fi
fi

existing_rpc=$(sed -n 's/^[[:space:]]*blockchain_rpc_endpoint[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -n 1)
existing_key=$(sed -n 's/^[[:space:]]*miner_key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -n 1)
[ -n "$existing_key" ] || { echo "Existing miner_key was not found; refusing to rewrite config." >&2; exit 1; }

BLOCKCHAIN_RPC_ENDPOINT="$existing_rpc"
PRIVATE_KEY=""
echo "Choose what you want to change:"
echo "1. Change RPC endpoint"
echo "2. Change miner key"
read -r -p "Enter your choice (1/2): " USER_CHOICE
case "$USER_CHOICE" in
    1)
        choose_json_rpc_endpoint
        read -r -p "Do you want to change the miner key as well? (yes/no): " CHANGE_MINER_KEY
        if [ "$CHANGE_MINER_KEY" = "yes" ]; then
            read -rsp "Enter your private key: " PRIVATE_KEY; echo
        fi
        ;;
    2)
        read -rsp "Enter your private key: " PRIVATE_KEY; echo
        read -r -p "Do you want to change the RPC endpoint as well? (yes/no): " CHANGE_RPC
        [ "$CHANGE_RPC" = "yes" ] && choose_json_rpc_endpoint
        ;;
    *) echo "Invalid choice. Exiting." >&2; exit 1 ;;
esac

[ -n "$BLOCKCHAIN_RPC_ENDPOINT" ] || BLOCKCHAIN_RPC_ENDPOINT="$existing_rpc"
require_rpc_chain "$BLOCKCHAIN_RPC_ENDPOINT"

candidate=$(mktemp)
backup="${CONFIG_FILE}.valley-backup.$(date -u +%Y%m%dT%H%M%SZ)"
cleanup() { rm -f "$candidate"; }
trap cleanup EXIT
cp "$CONFIG_FILE" "$candidate"
chmod 600 "$candidate"

sed -i -E "s|^[[:space:]]*blockchain_rpc_endpoint[[:space:]]*=.*|blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"|" "$candidate"
if [ -n "$PRIVATE_KEY" ]; then
    sed -i -E "s|^[[:space:]]*miner_key[[:space:]]*=.*|miner_key = \"$PRIVATE_KEY\"|" "$candidate"
fi
sed -i -E \
    -e 's|^[[:space:]]*listen_address[[:space:]]*=.*|listen_address = "0.0.0.0:5678"|' \
    -e 's|^[[:space:]]*listen_address_admin[[:space:]]*=.*|listen_address_admin = "127.0.0.1:5679"|' \
    -e 's|^[[:space:]]*rpc_enabled[[:space:]]*=.*|rpc_enabled = true|' \
    "$candidate"

grep -Fq "blockchain_rpc_endpoint = \"$BLOCKCHAIN_RPC_ENDPOINT\"" "$candidate" || { echo "Candidate config validation failed." >&2; exit 1; }
grep -Fq 'listen_address_admin = "127.0.0.1:5679"' "$candidate" || { echo "Admin RPC loopback guard missing." >&2; exit 1; }

cp "$CONFIG_FILE" "$backup"
chmod 600 "$backup"
install -m 0600 "$candidate" "$CONFIG_FILE.valley-new"

sudo systemctl stop "$SERVICE_NAME"
mv -f "$CONFIG_FILE.valley-new" "$CONFIG_FILE"
if ! sudo systemctl restart "$SERVICE_NAME" || ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Storage service failed after config change; restoring previous config." >&2
    cp "$backup" "$CONFIG_FILE"
    sudo systemctl restart "$SERVICE_NAME" || true
    exit 1
fi

echo "Storage Node configuration updated successfully."
echo "Backup retained at: $backup"
