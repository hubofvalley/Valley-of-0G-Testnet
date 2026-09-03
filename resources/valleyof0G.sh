#!/bin/bash

# Runtime security boundary: executable helpers are loaded from an immutable
# repository commit when this entrypoint is executed remotely. Local checkouts
# always prefer sibling files so development/testing remains offline-friendly.
readonly VALLEY_RUNTIME_REF="6a84d2b39804b3fbe1641e90a4eb3ce4ad0da8ad"
readonly VALLEY_REPOSITORY="hubofvalley/Valley-of-0G-Testnet"
readonly VALLEY_EXPECTED_EVM_CHAIN_ID="16602"

validate_runtime_ref() {
    [[ "$VALLEY_RUNTIME_REF" =~ ^[0-9a-f]{40}$ ]]
}

run_repository_script() {
    local relative_path=$1
    shift
    local script_dir local_script manifest tmpdir remote_script remote_manifest rc

    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
    local_script="${script_dir}/${relative_path#resources/}"
    manifest="${script_dir}/../VERSIONS.json"
    if [ -n "$script_dir" ] && [ -f "$local_script" ]; then
        VALLEY_MANIFEST_PATH="$manifest" VALLEY_RUNTIME_REF="$VALLEY_RUNTIME_REF" bash "$local_script" "$@"
        return $?
    fi

    if ! validate_runtime_ref; then
        echo "Runtime helper blocked: VALLEY_RUNTIME_REF must be a full 40-character Git commit SHA." >&2
        return 2
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "Runtime helper blocked: curl is required." >&2
        return 2
    fi

    tmpdir=$(mktemp -d)
    remote_script="$tmpdir/helper.sh"
    remote_manifest="$tmpdir/VERSIONS.json"
    if ! curl -fsSL "https://raw.githubusercontent.com/${VALLEY_REPOSITORY}/${VALLEY_RUNTIME_REF}/${relative_path}" -o "$remote_script"; then
        rm -rf "$tmpdir"
        echo "Failed to download $relative_path from pinned commit $VALLEY_RUNTIME_REF. Nothing was executed." >&2
        return 2
    fi
    if ! curl -fsSL "https://raw.githubusercontent.com/${VALLEY_REPOSITORY}/${VALLEY_RUNTIME_REF}/VERSIONS.json" -o "$remote_manifest"; then
        rm -rf "$tmpdir"
        echo "Failed to download VERSIONS.json from pinned commit $VALLEY_RUNTIME_REF. Nothing was executed." >&2
        return 2
    fi
    chmod +x "$remote_script"
    VALLEY_MANIFEST_PATH="$remote_manifest" VALLEY_RUNTIME_REF="$VALLEY_RUNTIME_REF" bash "$remote_script" "$@"
    rc=$?
    rm -rf "$tmpdir"
    return "$rc"
}

if [ "${1:-}" = "doctor" ] || [ "${1:-}" = "node-doctor" ]; then
    shift
    run_repository_script resources/vo0g_node_doctor.sh "$@"
    exit $?
fi

vo0g_rpc_chain_id() {
    local endpoint=$1 result
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    result=$(curl -fsS --connect-timeout 4 --max-time 8 \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "$endpoint" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)
    if [[ "$result" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf '%d\n' "$((16#${result#0x}))"
    elif [[ "$result" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$result"
    else
        return 1
    fi
}

vo0g_require_evm_chain() {
    local endpoint=$1 chain_id
    chain_id=$(vo0g_rpc_chain_id "$endpoint" || true)
    if [ "$chain_id" != "$VALLEY_EXPECTED_EVM_CHAIN_ID" ]; then
        echo -e "${RED:-}RPC rejected: ${endpoint} reports chain ${chain_id:-unavailable}; expected ${VALLEY_EXPECTED_EVM_CHAIN_ID}.${RESET:-}" >&2
        return 1
    fi
    return 0
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;214m'
RESET='\033[0m'
# Service/client detection - preserve existing Geth installs, prefer Reth only
# for a host with no execution client configured yet.
source "$HOME/.bash_profile" 2>/dev/null || true

if [ -z "${EXEC_CLIENT:-}" ]; then
    if [ -x "$HOME/go/bin/0g-reth" ] || systemctl cat 0g-reth >/dev/null 2>&1; then
        EXEC_CLIENT=reth
    elif [ -x "$HOME/go/bin/0g-geth" ] || systemctl cat 0g-geth >/dev/null 2>&1; then
        EXEC_CLIENT=geth
    else
        EXEC_CLIENT=reth
    fi
fi

if [ -z "${OG_SERVICE_NAME:-}" ]; then
    echo -e "${YELLOW}Service name configuration not found.${RESET}"
    read -p "Enter Consensus Service Name (default '0gchaind'): " INPUT_SVC
    OG_SERVICE_NAME=${INPUT_SVC:-0gchaind}
    echo "export OG_SERVICE_NAME=\"$OG_SERVICE_NAME\"" >> $HOME/.bash_profile
    export OG_SERVICE_NAME
fi

case "$EXEC_CLIENT" in
    geth)
        if [ -z "${OG_GETH_SERVICE_NAME:-}" ]; then
            read -r -p "Enter Geth Service Name (default '0g-geth'): " INPUT_GETH
            OG_GETH_SERVICE_NAME=${INPUT_GETH:-0g-geth}
        fi
        EL_SERVICE_NAME=$OG_GETH_SERVICE_NAME
        ;;
    reth)
        if [ -z "${OG_RETH_SERVICE_NAME:-}" ]; then
            read -r -p "Enter Reth Service Name (default '0g-reth'): " INPUT_RETH
            OG_RETH_SERVICE_NAME=${INPUT_RETH:-0g-reth}
        fi
        EL_SERVICE_NAME=$OG_RETH_SERVICE_NAME
        ;;
    *)
        echo "Unsupported EXEC_CLIENT=$EXEC_CLIENT; expected geth or reth." >&2
        exit 1
        ;;
esac

if ! [[ "$OG_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ && "$EL_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    echo "Invalid systemd service name in profile/input." >&2
    exit 1
fi

LOGO="
 __      __     _  _                        __    ___    _____ 
 \ \    / /    | || |                      / _|  / _ \  / ____|
  \ \  / /__ _ | || |  ___  _   _    ___  | |_  | | | || |  __ 
  _\ \/ // __ || || | / _ \| | | |  / _ \ |  _| | | | || | |_ |
 | |\  /| (_| || || ||  __/| |_| | | (_) || |   | |_| || |__| |
 | |_\/  \__,_||_||_| \___| \__, |  \___/ |_|    \___/  \_____|
 | '_ \ | | | |              __/ |                             
 | |_) || |_| |             |___/                              
 |____/  \__, |                                                
          __/ |                                                
         |___/                                                 
 __                                   
/__ __ __ __   _|   \  / __ | |  _    
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"

INTRO="
Valley of 0G by ${ORANGE}Grand Valley${RESET}

${GREEN}0G Validator Node System Requirements${RESET}
${YELLOW}| Category  | Requirements                   |
| --------- | ------------------------------ |
| CPU       | 8 cores                        |
| RAM       | 64+ GB                         |
| Storage   | 1+ TB NVMe SSD                 |
| Bandwidth | 100 MBps for Download / Upload |${RESET}

validator node managed binary version: ${CYAN}v3.0.8${RESET}
- consensus client service file name: ${CYAN}${OG_SERVICE_NAME}.service${RESET}
- execution client: ${CYAN}${EXEC_CLIENT}${RESET} (${CYAN}${EL_SERVICE_NAME}.service${RESET})
current consensus network: ${CYAN}0G-testnet-galileo${RESET}
current EVM chain ID: ${CYAN}16602 (Galileo Testnet)${RESET}

------------------------------------------------------------------

${GREEN}Storage Node System Requirements${RESET}
${YELLOW}| Category  | Requirements                   |
| --------- | ------------------------------ |
| CPU       | 8+ cores                       |
| RAM       | 32+ GB                         |
| Storage   | 500GB / 1TB NVMe SSD           |
| Bandwidth | 100 MBps for Download / Upload |${RESET}

storage node current binary version: ${CYAN}v1.1.0${RESET}

------------------------------------------------------------------

${GREEN}Storage KV System Requirements${RESET}
${YELLOW}| Category | Requirements                                |
| -------- | ------------------------------------------- |
| CPU      | 8+ cores                                    |
| RAM      | 32+ GB                                      |
| Storage  | Matches the size of kv streams it maintains |${RESET}

storage kvs current binary version: ${CYAN}v1.4.0${RESET}

------------------------------------------------------------------
"

PRIVACY_SAFETY_STATEMENT="
${YELLOW}Privacy and Safety Statement${RESET}

${GREEN}No User Data Stored Externally${RESET}
- This script does not store any user data externally. All operations are performed locally on your machine.

${GREEN}No Phishing Links${RESET}
- This script does not contain any phishing links. All URLs and commands are provided for legitimate purposes related to 0G validator node operations.

${GREEN}Security Best Practices${RESET}
- Always verify the integrity of the script and its source.
- Ensure you are running the script in a secure environment.
- Be cautious when entering sensitive information such as wallet names and addresses.

${GREEN}Disclaimer${RESET}
- The authors of this script are not responsible for any misuse or damage caused by the use of this script.
- Use this script at your own risk.

${GREEN}Contact${RESET}
- If you have any concerns or questions, please contact us at letsbuidltogether@grandvalleys.com.
"

ENDPOINTS="${GREEN}
Galileo endpoint status:${RESET}
- official EVM RPC: ${BLUE}https://evmrpc-testnet.0g.ai${RESET} (managed network-identity reference; chain ID 16602)
- Grand Valley legacy Testnet RPC/REST endpoints: ${YELLOW}needs_live_repair; not used as a managed default${RESET}
- Grand Valley legacy peer helper: ${YELLOW}disabled until live endpoint verification is restored${RESET}

${GREEN}Connect with Zero Gravity (0G):${RESET}
- Official Website: ${BLUE}https://0g.ai/${RESET}
- X: ${BLUE}https://x.com/0G_labs${RESET}
- Official Docs: ${BLUE}https://docs.0g.ai/${RESET}

${GREEN}Connect with Grand Valley:${RESET}
- X: ${BLUE}https://x.com/bacvalley${RESET}
- GitHub: ${BLUE}https://github.com/hubofvalley${RESET}
- Valley of 0G Testnet repository: ${BLUE}https://github.com/hubofvalley/Valley-of-0G-Testnet${RESET}
- Email: ${BLUE}letsbuidltogether@grandvalleys.com${RESET}
"

# Display LOGO and wait for user input to continue
echo -e "$LOGO"
echo -e "$PRIVACY_SAFETY_STATEMENT"
echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
read -r

# Display INTRO section and wait for user input to continue
echo -e "$INTRO"
echo -e "$ENDPOINTS"
echo -e "${YELLOW}\nPress Enter to continue${RESET}"
read -r
export PATH="$PATH:$HOME/go/bin"

# Validator Node Functions
function deploy_validator_node() {
    clear
    echo -e "${RED}▓▒░ IMPORTANT DISCLAIMER AND TERMS ░▒▓${RESET}"
    echo -e "${YELLOW}1. SECURITY:${RESET}"
    echo -e "- This script ${GREEN}DOES NOT${RESET} send any data outside your server"
    echo "- All operations are performed locally"
    echo "- You are encouraged to audit the script at:"
    echo -e "  ${BLUE}https://github.com/hubofvalley/Valley-of-0G-Testnet/blob/main/resources/0g_validator_node_galileo_install.sh${RESET}"

    echo -e "\n${YELLOW}2. SYSTEM IMPACT:${RESET}"
    echo -e "${GREEN}New Services:${RESET}"
    echo -e "  • ${CYAN}${OG_SERVICE_NAME}.service${RESET} (Consensus Client)"
    echo -e "  • ${CYAN}${EL_SERVICE_NAME}.service${RESET} (Execution Client; current profile: ${EXEC_CLIENT})"
    
    echo -e "\n${RED}Existing Services to be Replaced:${RESET}"
    echo -e "  • ${CYAN}0gchaind${RESET}"
    echo -e "  • ${CYAN}0g-geth / 0g-reth${RESET} (only the selected managed client is active)"
    echo -e "  • ${CYAN}0ggeth${RESET}"
    
    echo -e "\n${GREEN}Port Configuration:${RESET}"
    echo -e "Ports will be adjusted based on your input (example if you enter 28):"
    echo -e "  • ${CYAN}28657${RESET} (RPC) <-- 26657"
    echo -e "  • ${CYAN}28656${RESET} (P2P) <-- 26656"
    echo -e "  • ${CYAN}28545${RESET} (EVM-RPC) <-- 8545"
    echo -e "  • ${CYAN}28546${RESET} (WebSocket) <-- 8546"
    
    echo -e "\n${GREEN}Directories:${RESET}"
    echo -e "  • ${CYAN}$HOME/.0gchaind${RESET}"

    echo -e "\n${YELLOW}3. REQUIREMENTS:${RESET}"
    echo "- CPU: 8+ cores, RAM: 64+ GB, Storage: 1TB+ NVMe SSD"
    echo "- Ubuntu 22.04/24.04 recommended"

    echo -e "\n${YELLOW}4. VALIDATOR RESPONSIBILITIES:${RESET}"
    echo "- As a validator, you'll need to:"
    echo "  - Maintain good uptime (recommended 99%+)"
    echo "  - Keep your node software updated"
    echo "  - Regularly backup your keys and data"
    echo "- The network has slashing mechanisms to:"
    echo "  - Encourage validator reliability"
    echo "  - Prevent malicious behavior"

    echo -e "\n${GREEN}By continuing you agree to these terms.${RESET}"
    read -p $'\n\e[33mDo you want to proceed with installation? (yes/no): \e[0m' confirm
    
    if [[ "${confirm,,}" != "yes" ]]; then
        echo -e "${RED}Installation cancelled by user.${RESET}"
        menu
        return
    fi

    echo -e "\n${GREEN}Starting installation...${RESET}"
    echo -e "${YELLOW}This may take 1-5 minutes. Please don't interrupt the process.${RESET}"
    sleep 2

    run_repository_script resources/0g_validator_node_galileo_install.sh
    source "$HOME/.bash_profile" 2>/dev/null || true
    EXEC_CLIENT=${EXEC_CLIENT:-geth}
    if [ "$EXEC_CLIENT" = "reth" ]; then
        EL_SERVICE_NAME=${OG_RETH_SERVICE_NAME:-0g-reth}
    else
        EL_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}
    fi
    menu
}

function manage_validator_node() {
    echo "Choose an option:"
    echo "1. Update Validator Node Version (preserves the currently selected execution client)"
    echo "2. Back"
    read -p "Enter your choice (1/2): " choice

    case $choice in
        1)
            run_repository_script resources/0g_validator_node_update_manual.sh
            menu
            ;;
        2)
            menu
            ;;
        *)
            echo "Invalid choice. Please select a valid option."
            ;;
    esac
}

# Function to migrate to Cosmovisor


function apply_snapshot() {
     run_repository_script resources/apply_snapshot.sh
     menu
}

function install_0gchain_app() {
    local archive="galileo-v3.0.8.tar.gz"
    local expected_sha256="b9c008865513c06e2cf75d7e2daee27f739356a45e505e492dcffe70b90457a7"
    local url="https://github.com/0gfoundation/0gchain-NG/releases/download/v3.0.8/${archive}"
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "Downloading and installing managed 0gchaind v3.0.8..."
    if ! curl -fL --retry 3 "$url" -o "$tmpdir/$archive"; then
        rm -rf "$tmpdir"
        echo "Download failed. Nothing was installed." >&2
        return 1
    fi
    if ! printf '%s  %s\n' "$expected_sha256" "$tmpdir/$archive" | sha256sum --check; then
        rm -rf "$tmpdir"
        echo "Checksum verification failed. Nothing was installed." >&2
        return 1
    fi
    tar -xzf "$tmpdir/$archive" -C "$tmpdir"
    if [ ! -x "$tmpdir/galileo-v3.0.8/bin/0gchaind" ]; then
        rm -rf "$tmpdir"
        echo "Verified archive is missing bin/0gchaind." >&2
        return 1
    fi
    mkdir -p "$HOME/go/bin"
    install -m 0755 "$tmpdir/galileo-v3.0.8/bin/0gchaind" "$HOME/go/bin/0gchaind"
    rm -rf "$tmpdir"
    echo "0gchaind v3.0.8 installed successfully at $HOME/go/bin/0gchaind"
    menu
}

# function create_validator() {
#     read -p "Enter wallet name: " WALLET
#     read -p "Enter validator name (moniker): " MONIKER
#     read -p "Enter your identity: " IDENTITY
#     read -p "Enter your website URL: " WEBSITE
#     read -p "Enter your email: " EMAIL
#
#     0gchaind tx staking create-validator \
#     --amount=1000000ua0gi \
#     --pubkey=$(0gchaind tendermint show-validator) \
#     --moniker=$MONIKER \
#     --chain-id=$OG_CHAIN_ID \
#     --commission-rate=0.10 \
#     --commission-max-rate=0.20 \
#     --commission-max-change-rate=0.01 \
#     --min-self-delegation=1 \
#     --from=$WALLET \
#     --identity=$IDENTITY \
#     --website=$WEBSITE \
#     --security-contact=$EMAIL \
#     --details="lets buidl 0g together" \
#     --gas auto --gas-adjustment 1.5 \
#     -y
#     menu
# }

function query_balance() {
    echo -e "${CYAN}Select an option:${RESET}"
    echo "1. Query balance of EVM address"
    echo "2. Back"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            read -p "Enter the EVM address to query: " evm_address
            ;;
        2)
            menu
            return
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${RESET}"
            query_balance
            return
            ;;
    esac

    local balance_rpc="https://evmrpc-testnet.0g.ai"
    if ! vo0g_require_evm_chain "$balance_rpc"; then
        echo -e "${RED}Balance query blocked because the RPC chain could not be verified.${RESET}"
        return 1
    fi
    echo -e "${CYAN}Fetching balance from verified Galileo RPC for $evm_address...${RESET}"
    curl -fsS -X POST "$balance_rpc" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\":\"2.0\",
            \"method\":\"eth_getBalance\",
            \"params\": [\"$evm_address\", \"latest\"],
            \"id\":16602
        }" | jq -r '.result' | awk '{printf "Balance of %s: %0.18f A0GI\n", "'"$evm_address"'", strtonum($1)/1e18}'

    echo -e "\n${YELLOW}Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

# function send_transaction() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     read -p "Enter sender wallet name: " SENDER_WALLET
#     read -p "Enter recipient wallet address: " RECIPIENT_ADDRESS
#     read -p "Enter amount to send (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#
#     AMOUNT_UAOGI=$(awk "BEGIN { printf \"%.0f\", $AMOUNT_AOGI * 1000000 }")
#
#     0gchaind tx bank send "$SENDER_WALLET" "$RECIPIENT_ADDRESS" "${AMOUNT_UAOGI}ua0gi" --chain-id "$OG_CHAIN_ID" --gas auto --gas-adjustment 1.5 -y
#
#     menu
# }

# function stake_tokens() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     DEFAULT_WALLET=$WALLET
#
#     read -p "Enter wallet name (leave empty to use current default wallet --> $DEFAULT_WALLET): " WALLET_NAME
#     if [ -z "$WALLET_NAME" ]; then
#         WALLET_NAME=$DEFAULT_WALLET
#     fi
#
#     echo "Choose an option:"
#     echo "1. Delegate to Grand Valley"
#     echo "2. Self-delegate"
#     echo "3. Delegate to another validator"
#     read -p "Enter your choice (1, 2, or 3): " CHOICE
#
#     # Prompt for RPC choice
#     read -p "Use your own RPC or Grand Valley's? (own/gv, leave empty for gv): " RPC_CHOICE
#     if [ -z "$RPC_CHOICE" ]; then
#         RPC_CHOICE="gv"
#     fi
#
#     case $CHOICE in
#         1)
#             read -p "Enter amount to stake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#             VAL="0gvaloper1gela3jtnmen0dmj2q5p0pne5y45ftshzs053x3"
#             ;;
#         2)
#             read -p "Enter amount to stake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#             VAL=$(0gchaind keys show "$WALLET_NAME" --bech val -a)
#             ;;
#         3)
#             read -p "Enter validator address: " VAL
#             read -p "Enter amount to stake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#             ;;
#         *)
#             echo "Invalid choice. Please enter 1, 2, or 3."
#             menu
#             return
#             ;;
#     esac
#
#     AMOUNT_UAOGI=$(awk "BEGIN { printf \"%.0f\", $AMOUNT_AOGI * 1000000 }")
#
#     if [ "$RPC_CHOICE" == "gv" ]; then
#         NODE="--node https://lightnode-rpc-0g.grandvalleys.com:443"
#     else
#         NODE=""
#     fi
#
#     0gchaind tx staking delegate "$VAL" "${AMOUNT_UAOGI}ua0gi" --from "$WALLET_NAME" --chain-id "$OG_CHAIN_ID" --gas auto --gas-adjustment 1.5 $NODE -y
#
#     menu
# }

# function unstake_tokens() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     DEFAULT_WALLET=$WALLET
#
#     read -p "Enter wallet name (leave empty to use current default wallet --> $DEFAULT_WALLET): " WALLET_NAME
#     if [ -z "$WALLET_NAME" ]; then
#         WALLET_NAME=$DEFAULT_WALLET
#     fi
#
#     read -p "Enter validator address: " VALIDATOR_ADDRESS
#     read -p "Enter amount to unstake (in AOGI, e.g. 10 = 10 AOGI): " AMOUNT_AOGI
#
#     # Prompt for RPC choice
#     read -p "Use your own RPC or Grand Valley's? (own/gv, leave empty for gv): " RPC_CHOICE
#     if [ -z "$RPC_CHOICE" ]; then
#         RPC_CHOICE="gv"
#     fi
#
#     AMOUNT_UAOGI=$(awk "BEGIN { printf \"%.0f\", $AMOUNT_AOGI * 1000000 }")
#
#     if [ "$RPC_CHOICE" == "gv" ]; then
#         NODE="--node https://lightnode-rpc-0g.grandvalleys.com:443"
#     else
#         NODE=""
#     fi
#
#     0gchaind tx staking unbond "$VALIDATOR_ADDRESS" "${AMOUNT_UAOGI}ua0gi" --from "$WALLET_NAME" --chain-id "$OG_CHAIN_ID" --gas auto --gas-adjustment 1.5 $NODE -y
#
#     menu
# }

# function unjail_validator() {
#     echo -e "\n${YELLOW}Available wallets:${RESET}"
#     0gchaind keys list
#
#     DEFAULT_WALLET=$WALLET
#
#     read -p "Enter wallet name to unjail (leave empty to use default --> $DEFAULT_WALLET): " WALLET_NAME
#     if [ -z "$WALLET_NAME" ]; then
#         WALLET_NAME=$DEFAULT_WALLET
#     fi
#
#     # Prompt for RPC choice
#     read -p "Use your own RPC or Grand Valley's? (own/gv, leave empty for gv): " RPC_CHOICE
#     if [ -z "$RPC_CHOICE" ]; then
#         RPC_CHOICE="gv"
#     fi
#
#     if [ "$RPC_CHOICE" == "gv" ]; then
#         NODE="--node https://lightnode-rpc-0g.grandvalleys.com:443"
#     else
#         NODE=""
#     fi
#
#     0gchaind tx slashing unjail --from "$WALLET_NAME" --chain-id "$OG_CHAIN_ID" --gas-adjustment 1.6 --gas auto --gas-prices 0.003ua0gi $NODE -y
#
#     menu
# }

# function export_evm_private_key() {
#     read -p "Enter wallet name: " WALLET_NAME
#     0gchaind keys unsafe-export-eth-key $WALLET_NAME
#     echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
#     read -r
#     menu
# }

# function restore_wallet() {
#     read -p "Enter wallet name: " WALLET_NAME
#     0gchaind keys add $WALLET_NAME --recover --eth
#     menu
# }

# function create_wallet() {
#     read -p "Enter wallet name: " WALLET_NAME
#     0gchaind keys add $WALLET_NAME --eth
#     menu
# }

function delete_validator_node() {
    sudo systemctl stop "$OG_SERVICE_NAME" "$EL_SERVICE_NAME"
    sudo systemctl disable "$OG_SERVICE_NAME" "$EL_SERVICE_NAME"
    sudo rm -f "/etc/systemd/system/${OG_SERVICE_NAME}.service" "/etc/systemd/system/${EL_SERVICE_NAME}.service"
    rm -rf "$HOME/galileo" "$HOME/.0gchaind"
    sed -i "/OG_/d" $HOME/.bash_profile
    sed -i "/EXEC_CLIENT/d" $HOME/.bash_profile
    echo "Validator node deleted successfully."
    menu
}

function show_validator_logs() {
    echo "Displaying Consensus Client and Execution Client (${EXEC_CLIENT}) Logs:"
    sudo journalctl -u "$OG_SERVICE_NAME" -u "$EL_SERVICE_NAME" -fn 100 --no-pager
    menu
}

function show_consensus_client_logs() {
    echo "Displaying Consensus Client Logs:"
    sudo journalctl -u ${OG_SERVICE_NAME} -fn 100
    menu
}

function show_geth_logs() {
    echo "Displaying Execution Client (${EXEC_CLIENT}) Logs:"
    sudo journalctl -u "$EL_SERVICE_NAME" -fn 100
    menu
}

function show_node_status() {
    port=$(grep -oP 'laddr = "tcp://(0.0.0.0|127.0.0.1):\K[0-9]+57' "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml")
    curl -fsS "http://127.0.0.1:$port/status" | jq
    realtime_block_hex=$(curl -fsS -X POST "https://evmrpc-testnet.0g.ai" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')
    local_el_hex=$(curl -fsS -X POST "http://127.0.0.1:${OG_PORT}545" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')
    if [[ "$realtime_block_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then
        realtime_block_height=$((16#${realtime_block_hex#0x}))
    else
        realtime_block_height="N/A"
    fi
    if [[ "$local_el_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then
        local_el_height=$((16#${local_el_hex#0x}))
    else
        local_el_height="N/A"
    fi
    node_height=$(curl -fsS "http://127.0.0.1:$port/status" | jq -r '.result.sync_info.latest_block_height')
    echo "Consensus client block height: $node_height"
    echo "Execution client (${EXEC_CLIENT}) block height: $local_el_height"
    block_difference="N/A"
    if [[ "$realtime_block_height" =~ ^[0-9]+$ && "$node_height" =~ ^[0-9]+$ ]]; then
        block_difference=$(( realtime_block_height - node_height ))
    fi
    echo "Real-time Block Height: $realtime_block_height"
    echo -e "${YELLOW}Block Difference:${RESET} $block_difference"

    # Add explanation for negative values
    if [[ "$block_difference" =~ ^-?[0-9]+$ ]] && (( block_difference < 0 )); then
        echo -e "${GREEN}Note:${RESET} A negative value is normal - this means 0G Official's Testnet RPC block height is currently behind your node's height"
    fi
    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function stop_validator_node() {
    sudo systemctl stop "$OG_SERVICE_NAME" "$EL_SERVICE_NAME"
    menu
}

function restart_validator_node() {
    sudo systemctl daemon-reload
    sudo systemctl restart "$EL_SERVICE_NAME"
    sudo systemctl restart "$OG_SERVICE_NAME"
    menu
}

# function backup_validator_key() {
#     cp $HOME/.0gchain/config/priv_validator_key.json $HOME/priv_validator_key.json
#     echo -e "\n${YELLOW}Your priv_vaidator_key.json file has been copied to $HOME${RESET}"
#     menu
# }

function add_peers() {
    echo "Select an option:"
    echo "1. Add peers manually"
    echo "2. Grand Valley automatic peer discovery (temporarily unavailable)"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            read -p "Enter peers (comma-separated): " peers
            echo "You have entered the following peers: $peers"
            read -p "Do you want to proceed? (yes/no): " confirm   
            if [[ $confirm == "yes" ]]; then
                sed -i -e "s|^persistent_peers *=.*|persistent_peers = \"$peers\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
                echo "Peers added manually."
            else
                echo "Operation cancelled. Returning to menu."
                menu
            fi
            ;;
        2)
            echo "Automatic Grand Valley Testnet peer discovery is disabled because the legacy public RPC endpoint has not passed current live verification."
            echo "Use manual peers from a currently verified Galileo source instead."
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            menu
            ;;
    esac
    echo "Now you can restart your Validator Node"
    menu
}

# Storage Node Functions
function deploy_storage_node() {
    run_repository_script resources/0g_storage_node_install.sh
    menu
}

function update_storage_node() {
    run_repository_script resources/0g_storage_node_update.sh
    menu
}

function apply_storage_node_snapshot() {
    clear
    # Display critical information
    echo -e "\033[0;31m▓▒░ CRITICAL NOTICE:\033[0m"
    echo -e "\033[0;33m░ Snapshot contains: \033[0;32mflow_db (blockchain data)\033[0m"
    echo -e "\033[0;33m░ Not included:      \033[38;5;214mdata_db (mining storage)\033[0m"
    echo -e "\033[0;32m░ Your data_db will auto-create when node starts\033[0m"
    echo -e "\033[0;31m░ \033[38;5;214m⚠ SECURITY WARNING: \033[0;31mNever use pre-made data_db!\033[0m"
    echo -e "\033[0;31m░               It would mine for someone else's wallet!\033[0m"
    echo -e "\033[0;36mDocumentation: \033[0;34mhttps://docs.0g.ai/run-a-node/storage-node#snapshot\033[0m\n"

    # Get explicit confirmation
    read -p $'\033[0;36mDo you accept these conditions? (y/N): \033[0m' agree
    if [[ "${agree,,}" != "y" ]]; then
        echo -e "\033[0;31mOperation cancelled by user\033[0m"
        sleep 1
        menu
        return
    fi

    # Contract selection loop
    while true; do
        clear
        echo -e "\033[0;36m▓▒░ Storage Node Contract Type\033[0m"
        echo -e "\033[0;32m1) Standard Contract\033[0m   (Not Available)"
        echo -e "\033[0;33m2) Turbo Contract\033[0m     (Disabled pending Galileo verification)"
        echo -e "\033[0;31m3) Cancel & Return\033[0m"
        
        read -p $'\033[0;34mSelect option [1-3]: \033[0m' contract_choice

        case $contract_choice in
            1)
                echo -e "\033[0;33mStandard Contract snapshot not available."
                echo -e "Please monitor official channels for updates!\033[0m"
                sleep 2
                ;;
            2)
                echo -e "\n\033[0;31m▓▒░ IMPORTANT: Post-Snapshot Downtime Expected ░▒▓\033[0m"
                echo -e "\033[0;33mAfter applying the snapshot, your storage node will experience"
                echo -e "several hours of downtime while the data_db automatically syncs."
                echo -e "This is NORMAL BEHAVIOR - no action is needed!\033[0m\n"
                echo -e "The node will resume normal operations once sync completes."
                echo -e "\033[0;36mProgress can be monitored via node logs.\033[0m"
                sleep 3

                echo -e "\n\033[0;32mInitializing Standard Contract snapshot...\033[0m"
                echo -e "\033[0;33mThis may take several minutes...\033[0m"
                if run_repository_script resources/0g_turbo_zgs_node_snapshot.sh; then
                    :
                else
                    snapshot_rc=$?
                    echo -e "\n\033[0;31mSnapshot was not applied (exit ${snapshot_rc}). Review the message above.\033[0m"
                    sleep 2
                    menu
                    return
                fi

                echo -e "\n\033[0;32m▓▒░ Snapshot Applied Successfully ░▒▓\033[0m"
                echo -e "\033[0;33mYour node is now syncing data_db - this will take several hours"
                echo -e "\033[0;31mDO NOT RESTART OR INTERRUPT THIS PROCESS\033[0m"
                echo -e "\033[0;33mMonitor progress with: \033[0;36mshow_storage_logs\033[0m"
                echo -e "Concerned? Check logs before contacting support!"
                sleep 3
                menu
                break
                ;;
            3)
                echo -e "\033[0;31mOperation aborted by user\033[0m"
                sleep 1
                menu
                break
                ;;
            *)
                echo -e "\033[0;31mInvalid selection! Please choose 1, 2, or 3.\033[0m"
                sleep 1
                ;;
        esac
    done
}

function delete_storage_node() {
    sudo systemctl stop zgs
    sudo systemctl disable zgs
    sudo rm -rf /etc/systemd/system/zgs.service
    sudo rm -r $HOME/0g-storage-node
    echo "Storage node deleted successfully."
    menu
}

function change_storage_node() {
    run_repository_script resources/0g_storage_node_change.sh
    menu
}

function show_storage_logs() {
    clear
    LOG_FILE="$HOME/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
    
    # Verify log file exists
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${RED}Error: Log file not found!${RESET}"
        echo -e "Verify node is running at: ${CYAN}$LOG_FILE${RESET}"
        sleep 2
        menu
        return
    fi

    # Show persistent instructions first
    echo -e "${CYAN}▓▒░ Storage Node Log Viewer ░▒▓${RESET}"
    echo -e "${YELLOW}┌────────────────────────────────────────────────────┐"
    echo -e "│ ${GREEN}Controls:${RESET}"
    echo -e "│ ${CYAN}Shift+F${RESET}                 - Auto-scroll new logs"
    echo -e "│ ${CYAN}Ctrl+C${RESET}                  - Pause auto-scroll"
    echo -e "│ ${CYAN}up arrow/down arrow${RESET}     - Scroll manually"
    echo -e "│ ${CYAN}/search${RESET}                 - Find text (n=next match)"
    echo -e "│ ${CYAN}Q${RESET}                       - Quit to menu"
    echo -e "└────────────────────────────────────────────────────┘${RESET}"
    
    # Wait for user confirmation
    read -n 1 -s -p $'\n\e[33mPress ANY KEY to view logs (Q to cancel): \e[0m' input
    echo ""
    
    if [[ "${input,,}" == "q" ]]; then
        echo -e "${GREEN}Operation cancelled. Returning to menu...${RESET}"
        sleep 1
        menu
        return
    fi

    # Show logs with instructions visible first
    echo -e "\n${CYAN}Loading logs...${RESET}"
    sleep 1  # Pause to see loading message
    less -R +F "$LOG_FILE"
    
    # Return to menu
    echo -e "\n${GREEN}Log viewing session closed. Returning to menu...${RESET}"
    sleep 1
    menu
}

function show_storage_status() {
    echo -e "${YELLOW}Storage Node Status:${RESET}"

    # Show Storage Node RPC Status
    curl -s -X POST http://localhost:5678 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}' \
        | jq

    config_file=$(sudo systemctl cat zgs | grep ExecStart | sed -E 's/.*--config[= ]([^ ]+)/\1/')

    if [[ -f "$config_file" ]]; then
        # Show ZGS node version
        if [[ -x "$HOME/0g-storage-node/target/release/zgs_node" ]]; then
            zgs_version=$("$HOME/0g-storage-node/target/release/zgs_node" --version)
            echo -e "\nZGS Node Version: ${GREEN}$zgs_version${RESET}"
        else
            echo -e "\n${RED}ZGS node binary not found or not executable!${RESET}"
        fi

        # Get blockchain RPC endpoint
        rpc_endpoint=$(grep -E '^blockchain_rpc_endpoint' "$config_file" | sed -E 's/.*= *"([^"]+)"/\1/')
        echo -e "\nBlockchain RPC Endpoint: ${GREEN}$rpc_endpoint${RESET}"

        # Get miner contract address
        contract_address=$(grep -E '^mine_contract_address' "$config_file" | sed -E 's/.*= *"([^"]+)"/\1/')
        echo -e "Miner Contract Address: ${GREEN}$contract_address${RESET}"

        # Detect contract type
        if [[ "$contract_address" == "0x1785c8683b3c527618eFfF78d876d9dCB4b70285" ]]; then
            echo -e "Contract Type: ${CYAN}Standard Contract${RESET}"
        elif [[ "$contract_address" == "0x3A0d1d67497Ad770d6f72e7f4B8F0BAbaa2A649C" ]]; then
            echo -e "Contract Type: ${CYAN}Turbo Contract${RESET}"
        else
            echo -e "Contract Type: ${RED}Unknown Contract${RESET}"
        fi

        # Get PoRA Transactions - UPDATED SECTION
        log_file="$HOME/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
        if [[ -f "$log_file" ]]; then
            hit_value=$(tail -n 100 "$log_file" | grep -oP 'hit: \K\d+' | tail -n1)
            if [[ -n "$hit_value" ]]; then
                echo -e "\nLatest PoRA TXs Count: ${GREEN}$hit_value${RESET}"
            else
                echo -e "\nLatest PoRA TXs Count: ${RED}No valid hits found in recent logs${RESET}"
            fi
        else
            echo -e "\nLatest PoRA TXs Count: ${RED}Log file not found${RESET}"
        fi
    else
        echo -e "\n${RED}Config file not found! Unable to determine contract or RPC info.${RESET}"
    fi

    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function stop_storage_node() {
    sudo systemctl stop zgs
    menu
}

function restart_storage_node() {
    sudo systemctl daemon-reload
    sudo systemctl restart zgs
    menu
}

# Storage KV Functions
function deploy_storage_kv() {
    run_repository_script resources/0g_storage_kv_install.sh
    menu
}

function show_storage_kv_logs() {
    sudo journalctl -u zgskv -fn 100
    menu
}

function delete_storage_kv() {
    sudo systemctl stop zgskv
    sudo systemctl disable zgskv
    sudo rm -rf /etc/systemd/system/zgskv.service
    sudo rm -r $HOME/0g-storage-kv
    echo "Storage KV deleted successfully."
    menu
}

function update_storage_kv() {
    run_repository_script resources/0g_storage_kv_update.sh
    menu
}

function stop_storage_kv() {
    sudo systemctl stop zgskv
    menu
}

function restart_storage_kv() {
    sudo systemctl daemon-reload
    sudo systemctl restart zgskv
    menu
}

# Show Grand Valley's Endpoints
function show_endpoints() {
    echo -e "$ENDPOINTS"
    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function show_guidelines() {
    echo -e "${CYAN}Guidelines on How to Use the Valley of 0G${RESET}"
    echo -e "${YELLOW}This tool is designed to help you manage your 0G nodes. Below are the guidelines on how to use it effectively:${RESET}"
    
    echo -e "${GREEN}1. Navigating the Menu${RESET}"
    echo "   - The menu is divided into several sections: Validator Node, Storage Node, Storage KV, Node Management, and Utilities."
    echo "   - To select an option, you can either:"
    echo "     a. Enter the corresponding number followed by the letter (e.g., 1a for Deploy Validator Node)."
    echo "     b. Enter the number, press Enter, and then enter the letter (e.g., 1 then a)."

    echo -e "${GREEN}2. Entering Choices${RESET}"
    echo "   - For any prompt that has choices, you only need to enter the number (1, 2, 3, etc.) or the letter (a, b, c, etc.)."
    echo "   - For y/n prompts, enter 'y' for yes and 'n' for no."
    echo "   - For yes/no prompts, enter 'yes' for yes and 'no' for no."

    echo -e "${GREEN}3. Running Commands${RESET}"
    echo "   - After selecting an option, the script will execute the corresponding commands."
    echo "   - Ensure you have the necessary permissions and dependencies installed for the commands to run successfully."

    echo -e "${GREEN}4. Exiting the Script${RESET}"
    echo "   - To exit the script, select option 8 from the main menu."
    echo "   - Remember to run 'source ~/.bash_profile' after exiting to apply any changes made to environment variables."

    echo -e "${GREEN}5. Additional Tips${RESET}"
    echo "   - Always backup your wallets and important data before performing operations like deleting nodes."
    echo "   - Valley's managed Galileo target is v3.0.8; live clean-host rehearsal remains a release gate."

    echo -e "${GREEN}6. Option Descriptions and Guides${RESET}"
    echo -e "${GREEN}Validator Node Options:${RESET}"
    echo "   a. Deploy/re-Deploy Validator Node: Sets up Galileo v3.0.8 with selectable Geth/Reth (Reth recommended for fresh installs)."
    echo "      - Guide: This will install all necessary components. Ensure your system meets requirements."
    echo "   b. Manage Validator Node: Update validator node version using the reviewed managed flow or return to menu."
    echo "   c. Add Peers: Manually add peers or use Grand Valley's peers."
    echo "      - Guide: Improves node connectivity and network participation."
    echo "   d. Show Node Status: Displays your validator's current status and health."
    echo "   e. Show Validator Logs: Views the validator's operational logs."
    echo "   f. Query Balance: Checks the balance of an EVM address."

    echo -e "${GREEN}Storage Node Options:${RESET}"
    echo "   a. Deploy Storage Node: Sets up a new storage node."
    echo "   b. Update Storage Node: Upgrades to the latest storage node version."
    echo "   c. Apply Storage Node Snapshot: Applies official snapshot for faster sync"
    echo -e "      - ${YELLOW}Important:${RESET} Always generate your own data_db - using others' will make you mine for them!"
    echo -e "      - Official docs: ${BLUE}https://docs.0g.ai/run-a-node/storage-node#snapshot${RESET}"
    echo "   d. Change Storage Node: Modifies storage node configuration."
    echo "   e. Show Storage Node Logs: Views storage node operational logs."
    echo "   f. Show Storage Node Status: Checks storage node health."

    echo -e "${GREEN}Storage KV Options:${RESET}"
    echo "   a. Deploy Storage KV: Sets up a key-value storage node."
    echo "   b. Show Storage KV Logs: Views KV node operational logs."
    echo "   c. Update Storage KV: Upgrades the KV node version."

    echo -e "${GREEN}Node Management:${RESET}"
    echo "   a. Restart Validator Node: Gracefully restarts validator."
    echo "   b. Restart Storage Node: Gracefully restarts storage node."
    echo "   c. Restart Storage KV: Gracefully restarts KV node."
    echo "   d. Stop Validator Node: Safely stops validator operations."
    echo "   e. Stop Storage Node: Safely stops storage operations."
    echo "   f. Stop Storage KV: Safely stops KV operations."
    echo "   g. Delete Validator Node: Removes validator (BACKUP WALLET & PRIV_KEYS FIRST!)."
    echo "   h. Delete Storage Node: Removes storage node."
    echo "   i. Delete Storage KV: Removes KV node."

    echo -e "${GREEN}Utilities:${RESET}"
    echo "   5. Install 0gchain App: Installs the managed CLI (v3.0.8) for transactions without running a node."
    echo "   6. Show Endpoints: Displays Grand Valley's public endpoints."
    echo "   7. Show Guidelines: Displays this help information."

    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

# Menu function
function menu() {
    realtime_block_height=$(curl -s -X POST "https://evmrpc-testnet.0g.ai" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | xargs printf "%d\n" 2>/dev/null)
    [ -z "$realtime_block_height" ] && realtime_block_height="N/A"
    local_rpc_port=$(grep -oP 'laddr = "tcp://(0.0.0.0|127.0.0.1):\K[0-9]+57' "$HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml" 2>/dev/null || echo "26657")
    local_node_height=$(curl -s "http://127.0.0.1:$local_rpc_port/status" 2>/dev/null | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null)
    [ -z "$local_node_height" ] && local_node_height="N/A (node not running)"
    block_difference="N/A"
    if [[ "$realtime_block_height" =~ ^[0-9]+$ && "$local_node_height" =~ ^[0-9]+$ ]]; then
        block_difference=$(( realtime_block_height - local_node_height ))
    fi
    echo -e "${ORANGE}Valley of 0G Testnet${RESET}"
    echo "Main Menu:"
    echo -e "${GREEN}1. Validator Node${RESET}"
    echo "    a. Deploy/re-Deploy Validator Node"
    echo "    b. Manage Validator Node"
    echo "    c. Apply Validator Node Snapshot"
    echo "    d. Add Peers"
    echo "    e. Show Node Status"
    echo "    f. Show Validator Node Logs (Consensus + ${EXEC_CLIENT})"
    echo "    g. Show Consensus Client Logs"
    echo "    h. Show Execution Client Logs (${EXEC_CLIENT})"
    echo "    i. Query Balance"
    echo -e "${GREEN}2. Storage Node${RESET}"
    echo "    a. Deploy Storage Node"
    echo "    b. Update Storage Node"
    echo "    c. Apply Storage Node Snapshot (Updated every 03.00 UTC)"
    echo "    d. Change Storage Node"
    echo "    e. Show Storage Node Logs"
    echo "    f. Show Storage Node Status"
    echo -e "${GREEN}3. Storage KV${RESET}"
    echo "    a. Deploy Storage KV"
    echo "    b. Show Storage KV Logs"
    echo "    c. Update Storage KV"
    echo -e "${GREEN}4. Node Management:${RESET}"
    echo "    a. Restart Validator Node"
    echo "    b. Restart Storage Node"
    echo "    c. Restart Storage KV"
    echo "    d. Stop Validator Node"
    echo "    e. Stop Storage Node"
    echo "    f. Stop Storage KV"
    echo "    g. Delete Validator Node (BACKUP YOUR SEEDS PHRASE/EVM-PRIVATE KEY AND priv_validator_key.json BEFORE YOU DO THIS)"
    echo "    h. Delete Storage Node"
    echo "    i. Delete Storage KV"
    echo -e "${GREEN}5. Install the 0gchain App (managed v3.0.8) only to execute transactions without running a node${RESET}"
    echo -e "${GREEN}6. Show Grand Valley's Endpoints${RESET}"
    echo -e "${YELLOW}7. Show Guidelines${RESET}"
    echo -e "${RED}8. Exit${RESET}"

    echo -e "Network Latest Block Height: ${GREEN}$realtime_block_height${RESET}"
    echo -e "Local Node Block Height: ${GREEN}$local_node_height${RESET}"
    echo -e "Block Difference: ${YELLOW}$block_difference${RESET}"
    echo -e "\n${YELLOW}Please run the following command to apply the changes after exiting the script:${RESET}"
    echo -e "${GREEN}source ~/.bash_profile${RESET}"
    echo -e "${YELLOW}This ensures the environment variables are set in your current bash session.${RESET}"
    echo -e "${GREEN}Let's Buidl 0G Together - Grand Valley${RESET}"
    read -p "Choose an option (e.g., 1a or 1 then a): " OPTION

    if [[ $OPTION =~ ^[1-8][a-i]$ ]]; then
        MAIN_OPTION=${OPTION:0:1}
        SUB_OPTION=${OPTION:1:1}
    else
        MAIN_OPTION=$OPTION
        if [[ $MAIN_OPTION =~ ^[1-4]$ ]]; then
            read -p "Choose a sub-option: " SUB_OPTION
        fi
    fi

    case $MAIN_OPTION in
        1)
            case $SUB_OPTION in
                a) deploy_validator_node ;;
                b) manage_validator_node ;;
                c) apply_snapshot ;;
                d) add_peers ;;
                e) show_node_status ;;
                f) show_validator_logs ;;
                g) show_consensus_client_logs ;;
                h) show_geth_logs ;;
                i) query_balance ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        2)
            case $SUB_OPTION in
                a) deploy_storage_node ;;
                b) update_storage_node ;;
                c) apply_storage_node_snapshot ;;
                d) change_storage_node ;;
                e) show_storage_logs ;;
                f) show_storage_status ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        3)
            case $SUB_OPTION in
                a) deploy_storage_kv ;;
                b) show_storage_kv_logs ;;
                c) update_storage_kv ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        4)
            case $SUB_OPTION in
                a) restart_validator_node ;;
                b) restart_storage_node ;;
                c) restart_storage_kv ;;
                d) stop_validator_node ;;
                e) stop_storage_node ;;
                f) stop_storage_kv ;;
                g) delete_validator_node ;;
                h) delete_storage_node ;;
                i) delete_storage_kv ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        5) install_0gchain_app ;;
        6) show_endpoints ;;
        7) show_guidelines ;;
        8) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
}

# Start menu
menu
