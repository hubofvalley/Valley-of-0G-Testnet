#!/bin/bash

set -u -o pipefail

readonly DOCTOR_VERSION="1.0.0"
readonly FALLBACK_EVM_CHAIN_ID="16602"
readonly FALLBACK_CONSENSUS_NETWORK=""
readonly FALLBACK_PUBLIC_EVM_RPC="https://evmrpc-testnet.0g.ai"

JSON_MODE=false
STRICT_MODE=false
for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --strict) STRICT_MODE=true ;;
        --version)
            echo "Valley of 0G Node Doctor (Testnet) ${DOCTOR_VERSION}"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

if $JSON_MODE && ! command -v jq >/dev/null 2>&1; then
    echo "Node Doctor --json requires jq." >&2
    exit 2
fi

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

profile_value() {
    local name=$1 default=$2 value=""
    if [ -f "$HOME/.bash_profile" ]; then
        value=$(sed -n "s/^export ${name}=\"\(.*\)\"$/\1/p" "$HOME/.bash_profile" | tail -n 1)
    fi
    printf '%s\n' "${value:-$default}"
}

EXPECTED_CHAIN_ID=$(manifest_value '.chain.evm_chain_id' "$FALLBACK_EVM_CHAIN_ID")
EXPECTED_CONSENSUS_NETWORK=$(manifest_value '.chain.consensus_network' "$FALLBACK_CONSENSUS_NETWORK")
MANAGED_VALIDATOR=$(manifest_value '.components.validator.bundle.version_current' 'unknown')
LATEST_VALIDATOR=$(manifest_value '.components.validator.bundle.upstream_latest' "$MANAGED_VALIDATOR")
MANAGED_STORAGE=$(manifest_value '.components.storage_node.version_current' 'unknown')
LATEST_STORAGE=$(manifest_value '.components.storage_node.upstream_latest' "$MANAGED_STORAGE")
MANAGED_KV=$(manifest_value '.components.storage_kv.version_current' 'unknown')
LATEST_KV=$(manifest_value '.components.storage_kv.upstream_latest' "$MANAGED_KV")
PUBLIC_EVM_RPC=${VO0G_PUBLIC_EVM_RPC:-$(manifest_value '.endpoints.official_evm_rpc' "$FALLBACK_PUBLIC_EVM_RPC")}

OG_PORT=${OG_PORT:-$(profile_value OG_PORT '26')}
OG_SERVICE_NAME=${OG_SERVICE_NAME:-$(profile_value OG_SERVICE_NAME '0gchaind')}
OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-$(profile_value OG_GETH_SERVICE_NAME '0g-geth')}
OG_RETH_SERVICE_NAME=${OG_RETH_SERVICE_NAME:-$(profile_value OG_RETH_SERVICE_NAME '0g-reth')}
EXEC_CLIENT=${EXEC_CLIENT:-$(profile_value EXEC_CLIENT 'geth')}

CONSENSUS_HOME=${VO0G_CONSENSUS_HOME:-$HOME/.0gchaind/0g-home/0gchaind-home}
CONSENSUS_CONFIG="$CONSENSUS_HOME/config/config.toml"
CONSENSUS_RPC=${VO0G_CONSENSUS_RPC:-http://127.0.0.1:${OG_PORT}657}
EVM_RPC=${VO0G_EVM_RPC:-http://127.0.0.1:${OG_PORT}545}

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
RESULTS=()

record() {
    local level=$1 code=$2 message=$3
    RESULTS+=("$level|$code|$message")
    case "$level" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    esac
}

rpc_result() {
    local endpoint=$1 method=$2
    curl -fsS --connect-timeout 3 --max-time 6 \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" \
        "$endpoint" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || true
}

hex_to_dec() {
    local value=$1
    if [[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf '%d\n' "$((16#${value#0x}))" 2>/dev/null || true
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
    fi
}

check_evm_rpc() {
    local code=$1 endpoint=$2 severity=$3 chain_hex chain_dec
    chain_hex=$(rpc_result "$endpoint" eth_chainId)
    chain_dec=$(hex_to_dec "$chain_hex")
    if [ "$chain_dec" = "$EXPECTED_CHAIN_ID" ]; then
        record PASS "$code" "$endpoint reports chain ID $EXPECTED_CHAIN_ID"
    elif [ -n "$chain_dec" ]; then
        record FAIL "$code" "$endpoint reports chain ID $chain_dec; expected $EXPECTED_CHAIN_ID"
    elif [ "$severity" = "required" ]; then
        record FAIL "$code" "$endpoint is unreachable or did not return eth_chainId"
    else
        record WARN "$code" "$endpoint is unreachable or did not return eth_chainId"
    fi
}

check_service() {
    local service=$1 code=$2 required=$3 state
    if ! command -v systemctl >/dev/null 2>&1; then
        record WARN "$code" "systemctl is unavailable; service state not checked"
        return
    fi
    state=$(systemctl is-active "$service" 2>/dev/null || true)
    if [ "$state" = "active" ]; then
        record PASS "$code" "$service.service is active"
    elif [ "$required" = "required" ]; then
        record FAIL "$code" "$service.service is ${state:-not found}"
    else
        record WARN "$code" "$service.service is ${state:-not found}"
    fi
}

if [ -n "$MANIFEST" ] && [ -f "$MANIFEST" ]; then
    record PASS manifest "managed manifest loaded from $MANIFEST"
else
    record WARN manifest "VERSIONS.json was not found; fallback network facts are in use"
fi

if command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    record PASS dependencies "curl and jq are available"
else
    record FAIL dependencies "curl and jq are required for RPC diagnostics"
fi

local_status=$(curl -fsS --connect-timeout 3 --max-time 6 "${CONSENSUS_RPC%/}/status" 2>/dev/null || true)
local_network=$(printf '%s' "$local_status" | jq -r '.result.node_info.network // empty' 2>/dev/null || true)
local_cl_height=$(printf '%s' "$local_status" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null || true)
local_catching_up=$(printf '%s' "$local_status" | jq -r '.result.sync_info.catching_up // empty' 2>/dev/null || true)
if [ -z "$EXPECTED_CONSENSUS_NETWORK" ] && [ -n "$local_network" ]; then
    record PASS consensus_network "local consensus RPC reports $local_network (no consensus network string is pinned yet)"
elif [ "$local_network" = "$EXPECTED_CONSENSUS_NETWORK" ]; then
    record PASS consensus_network "local consensus RPC reports $EXPECTED_CONSENSUS_NETWORK"
elif [ -n "$local_network" ]; then
    record FAIL consensus_network "local consensus RPC reports $local_network; expected $EXPECTED_CONSENSUS_NETWORK"
else
    record WARN consensus_network "local consensus RPC is not reachable at $CONSENSUS_RPC"
fi
if [ "$local_catching_up" = "false" ]; then
    record PASS consensus_sync "consensus client reports catching_up=false at height ${local_cl_height:-unknown}"
elif [ "$local_catching_up" = "true" ]; then
    record WARN consensus_sync "consensus client is still catching up at height ${local_cl_height:-unknown}"
fi

check_evm_rpc local_evm "$EVM_RPC" optional
check_evm_rpc public_evm "$PUBLIC_EVM_RPC" optional

local_el_hex=$(rpc_result "$EVM_RPC" eth_blockNumber)
local_el_height=$(hex_to_dec "$local_el_hex")
if [[ "$local_cl_height" =~ ^[0-9]+$ ]] && [[ "$local_el_height" =~ ^[0-9]+$ ]]; then
    if [ "$local_cl_height" -ge "$local_el_height" ]; then
        height_gap=$((local_cl_height - local_el_height))
    else
        height_gap=$((local_el_height - local_cl_height))
    fi
    if [ "$height_gap" -le 4 ]; then
        record PASS cl_el_height "CL/EL height gap is $height_gap blocks"
    else
        record WARN cl_el_height "CL/EL height gap is $height_gap blocks; inspect sync state before operating"
    fi
fi

check_service "$OG_SERVICE_NAME" consensus_service required
case "$EXEC_CLIENT" in
    reth)
        check_service "$OG_RETH_SERVICE_NAME" execution_service required
        other_state=$(systemctl is-active "$OG_GETH_SERVICE_NAME" 2>/dev/null || true)
        [ "$other_state" = "active" ] && record FAIL execution_xor "both geth and reth appear active" || record PASS execution_xor "reth selected; geth is not active"
        ;;
    geth)
        check_service "$OG_GETH_SERVICE_NAME" execution_service required
        other_state=$(systemctl is-active "$OG_RETH_SERVICE_NAME" 2>/dev/null || true)
        [ "$other_state" = "active" ] && record FAIL execution_xor "both geth and reth appear active" || record PASS execution_xor "geth selected; reth is not active"
        ;;
    *) record WARN execution_xor "EXEC_CLIENT=$EXEC_CLIENT is not a managed geth/reth selection" ;;
esac

if [ -f "$CONSENSUS_CONFIG" ]; then
    rpc_laddr=$(sed -n '/^\[rpc\]/,/^\[/ s/^[[:space:]]*laddr[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$CONSENSUS_CONFIG" | head -n 1)
    case "$rpc_laddr" in
        tcp://127.0.0.1:*|tcp://localhost:*) record PASS rpc_exposure "consensus RPC is loopback-bound" ;;
        "") record WARN rpc_exposure "could not determine consensus RPC bind address" ;;
        *) record WARN rpc_exposure "consensus RPC bind is $rpc_laddr; review intentional public exposure" ;;
    esac
else
    record WARN config "consensus config not found at $CONSENSUS_CONFIG"
fi

if command -v timedatectl >/dev/null 2>&1; then
    ntp_state=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
    [ "$ntp_state" = "yes" ] && record PASS time_sync "system clock reports NTP synchronized" || record WARN time_sync "NTP synchronization could not be confirmed"
fi

disk_path=$HOME
[ -d "$HOME/.0gchaind" ] && disk_path=$HOME/.0gchaind
free_kb=$(df -Pk "$disk_path" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ "$free_kb" =~ ^[0-9]+$ ]]; then
    if [ "$free_kb" -lt 52428800 ]; then
        record WARN disk "less than 50 GiB free on the validator filesystem"
    else
        record PASS disk "validator filesystem has at least 50 GiB free"
    fi
fi

if [ "$MANAGED_VALIDATOR" = "$LATEST_VALIDATOR" ]; then
    record PASS validator_release "managed validator bundle $MANAGED_VALIDATOR matches recorded upstream latest"
else
    record WARN validator_release "managed validator bundle $MANAGED_VALIDATOR; recorded upstream latest $LATEST_VALIDATOR"
fi
if [ "$MANAGED_STORAGE" = "$LATEST_STORAGE" ]; then
    record PASS storage_release "managed storage target $MANAGED_STORAGE matches recorded upstream latest"
else
    record WARN storage_release "managed storage target $MANAGED_STORAGE; upstream $LATEST_STORAGE requires compatibility review"
fi
if [ "$MANAGED_KV" = "$LATEST_KV" ]; then
    record PASS kv_release "managed Storage KV target $MANAGED_KV matches recorded upstream latest"
else
    record WARN kv_release "managed Storage KV target $MANAGED_KV; upstream $LATEST_KV requires compatibility review"
fi

if $JSON_MODE; then
    printf '{"network":"testnet","expected_chain_id":%s,"runtime_ref":"%s","pass":%d,"warn":%d,"fail":%d,"results":[' \
        "$EXPECTED_CHAIN_ID" "${VALLEY_RUNTIME_REF:-local}" "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
    first=true
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r level code message <<<"$row"
        $first || printf ','
        first=false
        jq -cn --arg level "$level" --arg code "$code" --arg message "$message" '{level:$level,code:$code,message:$message}'
    done
    printf ']}\n'
else
    echo "Valley of 0G Node Doctor - Testnet"
    echo "Expected EVM chain ID: $EXPECTED_CHAIN_ID"
    echo "Managed validator bundle: $MANAGED_VALIDATOR"
    echo
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r level code message <<<"$row"
        printf '[%s] %-20s %s\n' "$level" "$code" "$message"
    done
    echo
    echo "Summary: PASS=$PASS_COUNT WARN=$WARN_COUNT FAIL=$FAIL_COUNT"
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
if $STRICT_MODE && [ "$WARN_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
