#!/usr/bin/env bash
set -Eeuo pipefail

echo -e "\n--- 0G Testnet Node Setup (Validator or RPC) ---"

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST="${VALLEY_MANIFEST_PATH:-$SCRIPT_DIR/../VERSIONS.json}"

command -v jq >/dev/null 2>&1 || { echo "jq is required to read VERSIONS.json." >&2; exit 2; }
[ -r "$MANIFEST" ] || { echo "VERSIONS.json is required: $MANIFEST" >&2; exit 2; }
jq -e '.network == "0g-testnet"' "$MANIFEST" >/dev/null || { echo "Invalid 0G testnet manifest." >&2; exit 2; }

manifest_get() {
    local query=$1 value
    value=$(jq -er "$query | select(. != null and . != \"\")" "$MANIFEST" 2>/dev/null) || {
        echo "Required VERSIONS.json field missing: $query" >&2
        return 2
    }
    printf '%s\n' "$value"
}

GALILEO_VERSION=$(manifest_get '.components.validator.bundle.version_current')
GALILEO_RELEASE_REF=$(manifest_get '.components.validator.bundle.release_ref')
GALILEO_COMMIT=$(manifest_get '.components.validator.bundle.release_commit')
GALILEO_REPO=$(manifest_get '.components.validator.bundle.release_repo')
GALILEO_ARCHIVE=$(manifest_get '.components.validator.bundle.release_artifact')
GALILEO_SHA256=$(manifest_get '.components.validator.bundle.release_artifact_sha256')
EXPECTED_CHAIN_ID=$(manifest_get '.chain.evm_chain_id')
CONSENSUS_NETWORK=$(manifest_get '.chain.consensus_network')
GALILEO_EXTRACT_DIR="galileo-${GALILEO_VERSION}"
GALILEO_URL="${GALILEO_REPO}/releases/download/${GALILEO_RELEASE_REF}/${GALILEO_ARCHIVE}"

[[ "$GALILEO_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid Galileo release commit." >&2; exit 2; }
[[ "$GALILEO_SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid Galileo release digest." >&2; exit 2; }
[[ "$EXPECTED_CHAIN_ID" =~ ^[0-9]+$ ]] || { echo "Invalid Galileo EVM chain ID." >&2; exit 2; }

validate_service_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9_.@-]+$ ]]
}

persist_export() {
    local key=$1 value=$2 profile="$HOME/.bash_profile" tmp
    touch "$profile"
    tmp=$(mktemp)
    grep -v -E "^export[[:space:]]+${key}=" "$profile" > "$tmp" || true
    printf 'export %s=%q\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$profile"
}

service_belongs_to_current_instance() {
    local service=$1 fragment unit_user unit_workdir current_user
    fragment=$(systemctl show "$service" -p FragmentPath --value 2>/dev/null || true)
    [ -n "$fragment" ] || return 0
    [ -f "$fragment" ] || { echo "Cannot inspect existing $service service: $fragment" >&2; return 1; }
    unit_user=$(sed -n 's/^User=//p' "$fragment" | tail -n 1)
    unit_workdir=$(sed -n 's/^WorkingDirectory=//p' "$fragment" | tail -n 1)
    current_user=$(id -un)
    if [ "$unit_user" != "$current_user" ] || [ "$unit_workdir" != "$HOME/.0gchaind" ]; then
        echo "Redeploy blocked: $service.service belongs to another instance." >&2
        echo "Existing User=${unit_user:-unknown}, WorkingDirectory=${unit_workdir:-unknown}" >&2
        return 1
    fi
}

rpc_chain_id() {
    local endpoint=$1 result
    result=$(curl -fsS --connect-timeout 3 --max-time 6 \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "$endpoint" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)
    if [[ "$result" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf '%d\n' "$((16#${result#0x}))"
    elif [[ "$result" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$result"
    fi
}

for tool in curl jq sha256sum tar systemctl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool missing: $tool" >&2; exit 1; }
done

while true; do
    read -r -p "Deploy type? (validator/rpc): " NODE_TYPE
    NODE_TYPE=$(printf '%s' "$NODE_TYPE" | tr '[:upper:]' '[:lower:]')
    [[ "$NODE_TYPE" = "validator" || "$NODE_TYPE" = "rpc" ]] && break
    echo "Please type exactly 'validator' or 'rpc'."
done

echo -e "\n${CYAN}Select execution client:${RESET}"
echo "1) Geth - supported compatibility path"
echo "2) Reth - upstream-recommended fresh-install path"
while true; do
    read -r -p "Enter 1 or 2 [default: 2]: " EL_CHOICE
    EL_CHOICE=${EL_CHOICE:-2}
    case "$EL_CHOICE" in
        1) EXEC_CLIENT=geth; break ;;
        2) EXEC_CLIENT=reth; break ;;
        *) echo "Please enter 1 or 2." ;;
    esac
done

read -r -p "Enter your moniker: " MONIKER
[[ "$MONIKER" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || { echo "Moniker must be 1-64 characters using letters, numbers, dot, underscore, or dash." >&2; exit 1; }
read -r -p "Enter your preferred port prefix (default: 26): " OG_PORT
OG_PORT=${OG_PORT:-26}
[[ "$OG_PORT" =~ ^[0-9]{1,2}$ ]] || { echo "Port prefix must be one or two digits." >&2; exit 1; }
(( 10#$OG_PORT >= 1 && 10#$OG_PORT <= 64 )) || { echo "Port prefix must be between 1 and 64 so derived ports stay valid." >&2; exit 1; }
read -r -p "Do you want to enable the indexer? (yes/no): " ENABLE_INDEXER
read -r -p "Configure UFW firewall rules for 0G? (y/n): " SETUP_UFW

if [ "$NODE_TYPE" = "validator" ]; then
    read -r -p "Enter Holesky Testnet ETH RPC endpoint (ETH_RPC_URL): " ETH_RPC_URL
    [[ "$ETH_RPC_URL" =~ ^https?://[^[:space:]]+$ ]] || { echo "ETH_RPC_URL must be a non-whitespace http(s) URL." >&2; exit 1; }
    read -r -p "Enter block range to fetch logs (BLOCK_NUM), e.g. 2000: " BLOCK_NUM
    [[ "$BLOCK_NUM" =~ ^[0-9]+$ ]] || { echo "BLOCK_NUM must be a positive integer." >&2; exit 1; }
fi

if [ -z "${OG_SERVICE_NAME:-}" ]; then
    read -r -p "Enter Consensus Service Name (default '0gchaind'): " OG_SERVICE_NAME
    OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
fi
validate_service_name "$OG_SERVICE_NAME" || { echo "Invalid consensus service name." >&2; exit 1; }

if [ "$EXEC_CLIENT" = "geth" ]; then
    if [ -z "${OG_GETH_SERVICE_NAME:-}" ]; then
        read -r -p "Enter Geth Service Name (default '0g-geth'): " OG_GETH_SERVICE_NAME
        OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}
    fi
    validate_service_name "$OG_GETH_SERVICE_NAME" || { echo "Invalid Geth service name." >&2; exit 1; }
    EL_SERVICE_NAME=$OG_GETH_SERVICE_NAME
else
    if [ -z "${OG_RETH_SERVICE_NAME:-}" ]; then
        read -r -p "Enter Reth Service Name (default '0g-reth'): " OG_RETH_SERVICE_NAME
        OG_RETH_SERVICE_NAME=${OG_RETH_SERVICE_NAME:-0g-reth}
    fi
    validate_service_name "$OG_RETH_SERVICE_NAME" || { echo "Invalid Reth service name." >&2; exit 1; }
    EL_SERVICE_NAME=$OG_RETH_SERVICE_NAME
fi

echo "Using services: ${OG_SERVICE_NAME}.service and ${EL_SERVICE_NAME}.service"

STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED_ARCHIVE="$STAGE_DIR/$GALILEO_ARCHIVE"
echo "Downloading Galileo $GALILEO_VERSION before touching the running node..."
curl -fL --retry 3 "$GALILEO_URL" -o "$STAGED_ARCHIVE"
printf '%s  %s\n' "$GALILEO_SHA256" "$STAGED_ARCHIVE" | sha256sum --check
tar -xzf "$STAGED_ARCHIVE" -C "$STAGE_DIR"
STAGED_BUNDLE="$STAGE_DIR/$GALILEO_EXTRACT_DIR"
[ -d "$STAGED_BUNDLE/$NODE_TYPE" ] || { echo "Verified archive is missing $NODE_TYPE profile." >&2; exit 1; }
[ -x "$STAGED_BUNDLE/bin/0gchaind" ] || { echo "Verified archive is missing bin/0gchaind." >&2; exit 1; }
[ -x "$STAGED_BUNDLE/bin/geth" ] || { echo "Verified archive is missing bin/geth." >&2; exit 1; }
[ -x "$STAGED_BUNDLE/bin/reth" ] || { echo "Verified archive is missing bin/reth." >&2; exit 1; }
archive_network=$(jq -r '.chain_id // empty' "$STAGED_BUNDLE/$NODE_TYPE/0g-home/0gchaind-home/config/genesis.json")
[ "$archive_network" = "$CONSENSUS_NETWORK" ] || { echo "Verified archive consensus network mismatch: ${archive_network:-missing}." >&2; exit 1; }
archive_chain=$(sed -n -E 's/^[[:space:]]*NetworkId[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$STAGED_BUNDLE/$NODE_TYPE/geth-config.toml" | head -n 1)
[ "$archive_chain" = "$EXPECTED_CHAIN_ID" ] || { echo "Verified archive EVM chain mismatch: ${archive_chain:-missing}." >&2; exit 1; }

# Resolve the externally advertised P2P address before the destructive gate.
# A transient IP-discovery failure must never leave a previously working node deleted.
EXTERNAL_IP=$(curl -fsS --connect-timeout 3 --max-time 6 https://api.ipify.org || true)
[[ "$EXTERNAL_IP" =~ ^[0-9a-fA-F:.]+$ ]] || { echo "Could not determine a safe external IP for P2P advertisement; redeploy was not started." >&2; exit 1; }

for candidate_service in 0gchaind "$OG_SERVICE_NAME" 0g-geth 0ggeth 0g-reth reth "${OG_GETH_SERVICE_NAME:-_skip_}" "${OG_RETH_SERVICE_NAME:-_skip_}"; do
    service_belongs_to_current_instance "$candidate_service" || exit 1
done

REDEPLOY_BACKUP_DIR="$HOME/valley-0g-testnet-redeploy-backups/$(date -u +%Y%m%dT%H%M%SZ)"
OLD_CONS_HOME="$HOME/.0gchaind/0g-home/0gchaind-home"
PRESERVE_VALIDATOR_IDENTITY=no
if [ -f "$OLD_CONS_HOME/config/priv_validator_key.json" ]; then
    mkdir -p "$REDEPLOY_BACKUP_DIR"
    chmod 700 "$REDEPLOY_BACKUP_DIR"
    cp "$OLD_CONS_HOME/config/priv_validator_key.json" "$REDEPLOY_BACKUP_DIR/priv_validator_key.json"
    [ -f "$OLD_CONS_HOME/config/node_key.json" ] && cp "$OLD_CONS_HOME/config/node_key.json" "$REDEPLOY_BACKUP_DIR/node_key.json"
    [ -f "$OLD_CONS_HOME/data/priv_validator_state.json" ] && cp "$OLD_CONS_HOME/data/priv_validator_state.json" "$REDEPLOY_BACKUP_DIR/priv_validator_state.json"
    chmod 600 "$REDEPLOY_BACKUP_DIR"/*.json
    PRESERVE_VALIDATOR_IDENTITY=yes
    echo -e "${YELLOW}Existing consensus validator identity/state will be preserved at:${RESET} $REDEPLOY_BACKUP_DIR"
fi

echo -e "${YELLOW}Verified Galileo $GALILEO_VERSION is staged. Redeploy replaces local Galileo node state.${RESET}"
echo "Fresh installs may choose Reth, but this workflow does not perform an in-place Geth->Reth database migration."
read -r -p "Type REDEPLOY-GALILEO to continue: " REDEPLOY_CONFIRM
[ "$REDEPLOY_CONFIRM" = "REDEPLOY-GALILEO" ] || { echo "Redeploy cancelled before services/data were changed."; exit 0; }

sudo systemctl stop 0gchaind "$OG_SERVICE_NAME" 2>/dev/null || true
sudo systemctl stop 0g-geth 0ggeth 0g-reth reth "${OG_GETH_SERVICE_NAME:-_skip_}" "${OG_RETH_SERVICE_NAME:-_skip_}" 2>/dev/null || true
sudo systemctl disable 0gchaind "$OG_SERVICE_NAME" 2>/dev/null || true
sudo systemctl disable 0g-geth 0ggeth 0g-reth reth "${OG_GETH_SERVICE_NAME:-_skip_}" "${OG_RETH_SERVICE_NAME:-_skip_}" 2>/dev/null || true
sudo rm -f /etc/systemd/system/0gchaind.service /etc/systemd/system/0g-geth.service /etc/systemd/system/0ggeth.service /etc/systemd/system/0g-reth.service /etc/systemd/system/reth.service
sudo rm -f "/etc/systemd/system/${OG_SERVICE_NAME}.service" "/etc/systemd/system/${OG_GETH_SERVICE_NAME:-_skip_}.service" "/etc/systemd/system/${OG_RETH_SERVICE_NAME:-_skip_}.service" 2>/dev/null || true
rm -f "$HOME/go/bin/0gchaind" "$HOME/go/bin/0g-geth" "$HOME/go/bin/0ggeth" "$HOME/go/bin/0g-reth" "$HOME/go/bin/reth"
rm -rf "$HOME/.0gchaind" "$HOME/galileo"

sudo apt-get update -y
sudo apt-get install -y curl jq htop tmux lz4 ufw iproute2
mkdir -p "$HOME/go/bin"
cp -a "$STAGED_BUNDLE" "$HOME/galileo"

install -m 0755 "$HOME/galileo/bin/0gchaind" "$HOME/go/bin/0gchaind"
if [ "$EXEC_CLIENT" = "geth" ]; then
    install -m 0755 "$HOME/galileo/bin/geth" "$HOME/go/bin/0g-geth"
else
    install -m 0755 "$HOME/galileo/bin/reth" "$HOME/go/bin/0g-reth"
fi

mkdir -p "$HOME/.0gchaind"
cp -a "$HOME/galileo/$NODE_TYPE/." "$HOME/.0gchaind/"

if [ "$EXEC_CLIENT" = "geth" ]; then
    "$HOME/go/bin/0g-geth" init --datadir "$HOME/.0gchaind/0g-home/geth-home" "$HOME/.0gchaind/geth-genesis.json"
else
    "$HOME/go/bin/0g-reth" init --chain "$HOME/.0gchaind/geth-genesis.json" --datadir "$HOME/.0gchaind/0g-home/reth-home"
    mkdir -p "$HOME/.0gchaind/config"
    ln -sf "$HOME/.0gchaind/0g-home/0gchaind-home/config/client.toml" "$HOME/.0gchaind/config/client.toml"
fi

"$HOME/go/bin/0gchaind" init "$MONIKER" --chain-id "$CONSENSUS_NETWORK" --home "$HOME/.0gchaind/tmp" --chaincfg.chain-spec testnet
cp "$HOME/.0gchaind/tmp/data/priv_validator_state.json" "$HOME/.0gchaind/0g-home/0gchaind-home/data/"
cp "$HOME/.0gchaind/tmp/config/node_key.json" "$HOME/.0gchaind/0g-home/0gchaind-home/config/"
cp "$HOME/.0gchaind/tmp/config/priv_validator_key.json" "$HOME/.0gchaind/0g-home/0gchaind-home/config/"

if [ "$PRESERVE_VALIDATOR_IDENTITY" = "yes" ]; then
    cp "$REDEPLOY_BACKUP_DIR/priv_validator_key.json" "$HOME/.0gchaind/0g-home/0gchaind-home/config/priv_validator_key.json"
    [ -f "$REDEPLOY_BACKUP_DIR/node_key.json" ] && cp "$REDEPLOY_BACKUP_DIR/node_key.json" "$HOME/.0gchaind/0g-home/0gchaind-home/config/node_key.json"
    [ -f "$REDEPLOY_BACKUP_DIR/priv_validator_state.json" ] && cp "$REDEPLOY_BACKUP_DIR/priv_validator_state.json" "$HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json"
    chmod 600 "$HOME/.0gchaind/0g-home/0gchaind-home/config/priv_validator_key.json"
fi

"$HOME/go/bin/0gchaind" jwt generate --home "$HOME/.0gchaind/0g-home/0gchaind-home" --chaincfg.chain-spec testnet
cp -f "$HOME/.0gchaind/0g-home/0gchaind-home/config/jwt.hex" "$HOME/.0gchaind/jwt.hex"
chmod 600 "$HOME/.0gchaind/jwt.hex"

CONFIG="$HOME/.0gchaind/0g-home/0gchaind-home/config"
GCONFIG="$HOME/.0gchaind/geth-config.toml"

sed -i "s/^moniker *=.*/moniker = \"$MONIKER\"/" "$CONFIG/config.toml"
sed -i "s|laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:${OG_PORT}656\"|" "$CONFIG/config.toml"
sed -i "s|laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://127.0.0.1:${OG_PORT}657\"|" "$CONFIG/config.toml"
sed -i "s|^proxy_app = .*|proxy_app = \"tcp://127.0.0.1:${OG_PORT}658\"|" "$CONFIG/config.toml"
sed -i "s|^pprof_laddr = .*|pprof_laddr = \"127.0.0.1:${OG_PORT}060\"|" "$CONFIG/config.toml"
sed -i "s|prometheus_listen_addr = \".*\"|prometheus_listen_addr = \"127.0.0.1:${OG_PORT}660\"|" "$CONFIG/config.toml"

if [ "$ENABLE_INDEXER" = "yes" ]; then
    sed -i -e 's/^indexer = "null"/indexer = "kv"/' "$CONFIG/config.toml"
else
    sed -i -e 's/^indexer = "kv"/indexer = "null"/' "$CONFIG/config.toml"
fi

sed -i "s|address = \".*:3500\"|address = \"127.0.0.1:${OG_PORT}500\"|" "$CONFIG/app.toml"
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" "$CONFIG/app.toml"
sed -i 's/^pruning *=.*/pruning = "custom"/' "$CONFIG/app.toml"
sed -i 's/^pruning-keep-recent *=.*/pruning-keep-recent = "100"/' "$CONFIG/app.toml"
sed -i 's/^pruning-interval *=.*/pruning-interval = "19"/' "$CONFIG/app.toml"

if [ "$EXEC_CLIENT" = "geth" ]; then
    grep -Eq '^OverrideStakingActivation[[:space:]]*=[[:space:]]*1767830400$' "$GCONFIG" || {
        echo "Verified v3.0.8 package is missing the expected staking activation setting." >&2
        exit 1
    }
    sed -i "s/^HTTPHost = .*/HTTPHost = \"127.0.0.1\"/" "$GCONFIG"
    sed -i "s/^HTTPPort = .*/HTTPPort = ${OG_PORT}545/" "$GCONFIG"
    sed -i "s/^WSHost = .*/WSHost = \"127.0.0.1\"/" "$GCONFIG"
    sed -i "s/^WSPort = .*/WSPort = ${OG_PORT}546/" "$GCONFIG"
    sed -i "s/^ListenAddr = .*/ListenAddr = \":${OG_PORT}303\"/" "$GCONFIG"
    sed -i "s/^DiscAddr = .*/DiscAddr = \":${OG_PORT}303\"/" "$GCONFIG"
    sed -i 's/^HTTP = .*/HTTP = "127.0.0.1"/' "$GCONFIG"
    sed -i "s/^Port = .*/Port = ${OG_PORT}901/" "$GCONFIG"
fi

if [[ "$SETUP_UFW" =~ ^[Yy]$ ]]; then
    sudo ufw allow 22/tcp comment "SSH Access"
    sudo ufw allow "${OG_PORT}303/tcp" comment "0G Testnet EL P2P"
    sudo ufw allow "${OG_PORT}303/udp" comment "0G Testnet EL discovery"
    sudo ufw allow "${OG_PORT}656/tcp" comment "0G Testnet CometBFT P2P"
    sudo ufw --force enable
fi

VALIDATOR_ENV_FILE="$HOME/.0gchaind/validator.env"
if [ "$NODE_TYPE" = "validator" ]; then
    umask 077
    printf 'ETH_RPC_URL=%s\nBLOCK_NUM=%s\n' "$ETH_RPC_URL" "$BLOCK_NUM" > "$VALIDATOR_ENV_FILE"
fi

if [ "$NODE_TYPE" = "validator" ]; then
sudo tee "/etc/systemd/system/${OG_SERVICE_NAME}.service" >/dev/null <<EOF_UNIT
[Unit]
Description=0gchaind Galileo Validator - ${OG_SERVICE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=testnet
EnvironmentFile=$VALIDATOR_ENV_FILE
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \
  --chaincfg.chain-spec testnet \
  --chaincfg.restaking.enabled \
  --chaincfg.restaking.symbiotic-rpc-dial-url \${ETH_RPC_URL} \
  --chaincfg.restaking.symbiotic-get-logs-block-range \${BLOCK_NUM} \
  --home $HOME/.0gchaind/0g-home/0gchaind-home \
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/kzg-trusted-setup.json \
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/jwt.hex \
  --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \
  --chaincfg.engine.rpc-dial-url=http://127.0.0.1:${OG_PORT}551 \
  --p2p.external_address=${EXTERNAL_IP}:${OG_PORT}656
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_UNIT
else
sudo tee "/etc/systemd/system/${OG_SERVICE_NAME}.service" >/dev/null <<EOF_UNIT
[Unit]
Description=0gchaind Galileo RPC - ${OG_SERVICE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=testnet
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \
  --chaincfg.chain-spec testnet \
  --home $HOME/.0gchaind/0g-home/0gchaind-home \
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/kzg-trusted-setup.json \
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/jwt.hex \
  --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \
  --chaincfg.engine.rpc-dial-url=http://127.0.0.1:${OG_PORT}551 \
  --p2p.external_address=${EXTERNAL_IP}:${OG_PORT}656
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_UNIT
fi

if [ "$EXEC_CLIENT" = "geth" ]; then
sudo tee "/etc/systemd/system/${EL_SERVICE_NAME}.service" >/dev/null <<EOF_UNIT
[Unit]
Description=0G Galileo Geth - ${EL_SERVICE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0g-geth \
  --config $HOME/.0gchaind/geth-config.toml \
  --datadir $HOME/.0gchaind/0g-home/geth-home \
  --http \
  --http.addr 127.0.0.1 \
  --http.port ${OG_PORT}545 \
  --ws \
  --ws.addr 127.0.0.1 \
  --ws.port ${OG_PORT}546 \
  --authrpc.addr 127.0.0.1 \
  --authrpc.port ${OG_PORT}551 \
  --discovery.port ${OG_PORT}303 \
  --port ${OG_PORT}303 \
  --networkid ${EXPECTED_CHAIN_ID}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_UNIT
else
sudo tee "/etc/systemd/system/${EL_SERVICE_NAME}.service" >/dev/null <<EOF_UNIT
[Unit]
Description=0G Galileo Reth - ${EL_SERVICE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0g-reth node \
  --chain $HOME/.0gchaind/geth-genesis.json \
  --http \
  --http.addr 127.0.0.1 \
  --http.port ${OG_PORT}545 \
  --http.api eth,net,web3,txpool \
  --authrpc.addr 127.0.0.1 \
  --authrpc.port ${OG_PORT}551 \
  --authrpc.jwtsecret $HOME/.0gchaind/jwt.hex \
  --datadir $HOME/.0gchaind/0g-home/reth-home \
  --ipcpath $HOME/.0gchaind/0g-home/reth-home/eth-engine.ipc \
  --engine.persistence-threshold 0 \
  --engine.memory-block-buffer-target 0 \
  --bootnodes=enode://4f70c6c95329427be4af2a233c9c2305896d37c21bca8c21e7efc36634a862bd5b96b0c4a8a9bb5787b53eb01472fe895aad170d0923f6ea56ebc5f94825c4f7@34.105.23.36:30303 \
  --port ${OG_PORT}303 \
  --nat extip:${EXTERNAL_IP}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_UNIT
fi

persist_export MONIKER "$MONIKER"
persist_export OG_PORT "$OG_PORT"
persist_export NODE_TYPE "$NODE_TYPE"
persist_export EXEC_CLIENT "$EXEC_CLIENT"
persist_export OG_SERVICE_NAME "$OG_SERVICE_NAME"
if [ "$EXEC_CLIENT" = "geth" ]; then
    persist_export OG_GETH_SERVICE_NAME "$OG_GETH_SERVICE_NAME"
else
    persist_export OG_RETH_SERVICE_NAME "$OG_RETH_SERVICE_NAME"
fi

sudo systemctl daemon-reload
sudo systemctl enable "$EL_SERVICE_NAME" "$OG_SERVICE_NAME"
sudo systemctl start "$EL_SERVICE_NAME"
if [ "$EXEC_CLIENT" = "reth" ]; then
    echo "Waiting for the Reth Engine API before starting consensus..."
    ready=no
    for _ in $(seq 1 30); do
        if ss -lnt 2>/dev/null | grep -q ":${OG_PORT}551[[:space:]]"; then ready=yes; break; fi
        sleep 1
    done
    [ "$ready" = "yes" ] || { echo "Reth Engine API did not become ready; consensus was not started." >&2; exit 1; }
fi
sudo systemctl start "$OG_SERVICE_NAME"
sleep 2
systemctl is-active --quiet "$EL_SERVICE_NAME" || { echo "$EL_SERVICE_NAME failed to become active." >&2; exit 1; }
systemctl is-active --quiet "$OG_SERVICE_NAME" || { echo "$OG_SERVICE_NAME failed to become active." >&2; exit 1; }

local_chain=""
for _ in $(seq 1 20); do
    local_chain=$(rpc_chain_id "http://127.0.0.1:${OG_PORT}545")
    [ "$local_chain" = "$EXPECTED_CHAIN_ID" ] && break
    sleep 1
done
[ "$local_chain" = "$EXPECTED_CHAIN_ID" ] || {
    echo "Post-install chain verification failed: local EL reports ${local_chain:-unavailable}; expected $EXPECTED_CHAIN_ID." >&2
    exit 1
}

echo -e "\n${GREEN}0G Galileo $GALILEO_VERSION installation completed.${RESET}"
echo "Consensus network: $CONSENSUS_NETWORK"
echo "EVM chain ID: $EXPECTED_CHAIN_ID"
echo "Execution client: $EXEC_CLIENT"
echo "Consensus service: ${OG_SERVICE_NAME}.service"
echo "Execution service: ${EL_SERVICE_NAME}.service"
echo "This code path is statically rebaselined to v3.0.8; clean-host/live validator rehearsal is still required before public release."
