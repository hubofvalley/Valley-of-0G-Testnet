#!/bin/bash

# ==== CONFIG ====
echo -e "\n--- 0G Testnet Node Setup (Validator or RPC) ---"

LOGO="
 __                                   
/__ ._ _. ._   _|   \  / _. | |  _    
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"
echo "$LOGO"

# Colours
GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"

# ===== CHOOSE NODE TYPE =====
while true; do
  read -p "Deploy type? (validator/rpc): " NODE_TYPE
  NODE_TYPE=$(echo "$NODE_TYPE" | tr '[:upper:]' '[:lower:]')
  if [[ "$NODE_TYPE" == "validator" || "$NODE_TYPE" == "rpc" ]]; then
    break
  else
    echo "Please type exactly 'validator' or 'rpc'."
  fi
done

# Prompt for MONIKER, OG_PORT, Indexer
read -p "Enter your moniker: " MONIKER
read -p "Enter your preferred port number: (leave empty to use default: 26) " OG_PORT
if [ -z "$OG_PORT" ]; then
    OG_PORT=26
fi
read -p "Do you want to enable the indexer? (yes/no): " ENABLE_INDEXER
read -p "Configure UFW firewall rules for 0G? (y/n): " SETUP_UFW

# Extra prompts for VALIDATOR
if [ "$NODE_TYPE" = "validator" ]; then
  read -p "Enter Holesky Testnet ETH RPC endpoint (ETH_RPC_URL): " ETH_RPC_URL
  while [ -z "$ETH_RPC_URL" ]; do
    echo "ETH_RPC_URL cannot be empty for validator mode."
    read -p "Enter Holesky Testnet ETH RPC endpoint (ETH_RPC_URL): " ETH_RPC_URL
  done
  read -p "Enter block range to fetch logs (BLOCK_NUM), e.g. 2000: " BLOCK_NUM
  while ! [[ "$BLOCK_NUM" =~ ^[0-9]+$ ]]; do
    echo "BLOCK_NUM must be a positive integer."
    read -p "Enter block range to fetch logs (BLOCK_NUM), e.g. 2000: " BLOCK_NUM
  done
fi

# Service Name Configuration (for multi-instance support)
if [ -z "$OG_SERVICE_NAME" ]; then
    read -p "Enter Consensus Service Name (default '0gchaind'): " OG_SERVICE_NAME
    OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
fi

if [ -z "$OG_GETH_SERVICE_NAME" ]; then
    read -p "Enter Geth Service Name (default '0g-geth'): " OG_GETH_SERVICE_NAME
    OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}
fi

echo "Using Service Names: ${OG_SERVICE_NAME} and ${OG_GETH_SERVICE_NAME}"

# Save env vars
{
  echo "export MONIKER=\"$MONIKER\""
  echo "export OG_PORT=\"$OG_PORT\""
  echo "export NODE_TYPE=\"$NODE_TYPE\""
  echo "export OG_SERVICE_NAME=\"$OG_SERVICE_NAME\""
  echo "export OG_GETH_SERVICE_NAME=\"$OG_GETH_SERVICE_NAME\""
  if [ "$NODE_TYPE" = "validator" ]; then
    echo "export ETH_RPC_URL=\"$ETH_RPC_URL\""
    echo "export BLOCK_NUM=\"$BLOCK_NUM\""
  fi
  echo 'export PATH=$PATH:$HOME/galileo/bin'
  } >> ~/.bash_profile
  source ~/.bash_profile

# ==== CLEANUP EXISTING INSTALLATION ====
echo -e "\n?? Cleaning up any existing 0G node installation..."

# Stop and disable services (uses both hardcoded and custom names for compatibility)
sudo systemctl stop 0gchaind ${OG_SERVICE_NAME} 2>/dev/null || true
sudo systemctl stop 0g-geth 0ggeth ${OG_GETH_SERVICE_NAME} 2>/dev/null || true
sudo systemctl disable 0gchaind ${OG_SERVICE_NAME} 2>/dev/null || true
sudo systemctl disable 0g-geth 0ggeth ${OG_GETH_SERVICE_NAME} 2>/dev/null || true
sudo rm -f /etc/systemd/system/0gchaind.service /etc/systemd/system/0g-geth.service /etc/systemd/system/0ggeth.service
sudo rm -f /etc/systemd/system/${OG_SERVICE_NAME}.service /etc/systemd/system/${OG_GETH_SERVICE_NAME}.service 2>/dev/null || true
sudo rm -f $HOME/go/bin/0gchaind $HOME/go/bin/0g-geth $HOME/go/bin/0ggeth
rm -rf $HOME/.0gchaind $HOME/galileo $HOME/galileo-v3.0.4 $HOME/galileo-v3.0.4.tar.gz

echo "? Cleanup complete."

# ==== DEPENDENCIES ====
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git wget htop tmux build-essential jq make lz4 gcc unzip ufw

# ==== INSTALL GO ====
cd $HOME && ver="1.22.5"
wget -q "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bash_profile
source ~/.bash_profile
[ ! -d ~/go/bin ] && mkdir -p ~/go/bin
go version

# Optional: Configure UFW based on chosen ports
if [[ "$SETUP_UFW" =~ ^[Yy]$ ]]; then
    sudo apt install -y ufw
    sudo ufw allow 22/tcp comment "SSH Access"
    sudo ufw allow ${OG_PORT}303/tcp comment "0g-geth Testnet P2P"
    sudo ufw allow ${OG_PORT}303/udp comment "0g-geth Testnet discovery"
    sudo ufw allow ${OG_PORT}656/tcp comment "0g Testnet CometBFT P2P"
    sudo ufw --force enable
    sudo ufw status verbose
fi

# ==== DOWNLOAD GALILEO v3.0.4 ====
cd $HOME
sudo rm -rf galileo
wget -q https://github.com/0gfoundation/0gchain-NG/releases/download/v3.0.4/galileo-v3.0.4.tar.gz -O galileo-v3.0.4.tar.gz
tar -xzvf galileo-v3.0.4.tar.gz
mv galileo-v3.0.4 galileo
sudo rm galileo-v3.0.4.tar.gz

# ==== MAKE BINARIES EXECUTABLE ====
sudo chmod +x $HOME/galileo/$NODE_TYPE/bin/geth
sudo chmod +x $HOME/galileo/$NODE_TYPE/bin/0gchaind

# ==== MOVE BINARIES ====
cp $HOME/galileo/$NODE_TYPE/bin/geth $HOME/go/bin/0g-geth
cp $HOME/galileo/$NODE_TYPE/bin/0gchaind $HOME/go/bin/0gchaind

# ==== INIT CHAIN ====
mkdir -p $HOME/.0gchaind/
cp -r $HOME/galileo/$NODE_TYPE/* $HOME/.0gchaind/
0g-geth init --datadir $HOME/.0gchaind/0g-home/geth-home $HOME/.0gchaind/geth-genesis.json
0gchaind init "$MONIKER" --home $HOME/.0gchaind/tmp --chaincfg.chain-spec testnet

# ==== COPY KEYS ====
cp $HOME/.0gchaind/tmp/data/priv_validator_state.json $HOME/.0gchaind/0g-home/0gchaind-home/data/
cp $HOME/.0gchaind/tmp/config/node_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/
cp $HOME/.0gchaind/tmp/config/priv_validator_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/

# ==== Generate JWT Authentication Token ====
0gchaind jwt generate --home $HOME/.0gchaind/0g-home/0gchaind-home --chaincfg.chain-spec testnet
cp -f $HOME/.0gchaind/0g-home/0gchaind-home/config/jwt.hex $HOME/.0gchaind/jwt.hex

# ==== CONFIG PATCH ====
CONFIG="$HOME/.0gchaind/0g-home/0gchaind-home/config"
GCONFIG="$HOME/.0gchaind/geth-config.toml"
EXTERNAL_IP=$(curl -4 -s ifconfig.me)

# config.toml
sed -i "s/^moniker *=.*/moniker = \"$MONIKER\"/" $CONFIG/config.toml
sed -i "s|laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:${OG_PORT}656\"|" $CONFIG/config.toml
sed -i "s|laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://127.0.0.1:${OG_PORT}657\"|" $CONFIG/config.toml
sed -i "s|^proxy_app = .*|proxy_app = \"tcp://127.0.0.1:${OG_PORT}658\"|" $CONFIG/config.toml
sed -i "s|^pprof_laddr = .*|pprof_laddr = \"0.0.0.0:${OG_PORT}060\"|" $CONFIG/config.toml
sed -i "s|prometheus_listen_addr = \".*\"|prometheus_listen_addr = \"0.0.0.0:${OG_PORT}660\"|" $CONFIG/config.toml

# indexer toggle
if [ "$ENABLE_INDEXER" = "yes" ]; then
  sed -i -e 's/^indexer = "null"/indexer = "kv"/' $CONFIG/config.toml
  echo "Indexer enabled."
else
  sed -i -e 's/^indexer = "kv"/indexer = "null"/' $CONFIG/config.toml
  echo "Indexer disabled."
fi

# app.toml
sed -i "s|address = \".*:3500\"|address = \"127.0.0.1:${OG_PORT}500\"|" $CONFIG/app.toml
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" $CONFIG/app.toml
sed -i "s/^pruning *=.*/pruning = \"custom\"/" $CONFIG/app.toml
sed -i "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $CONFIG/app.toml
sed -i "s/^pruning-interval *=.*/pruning-interval = \"19\"/" $CONFIG/app.toml

# geth-config.toml
sed -i "s/HTTPPort = .*/HTTPPort = ${OG_PORT}545/" $GCONFIG
sed -i "s/WSPort = .*/WSPort = ${OG_PORT}546/" $GCONFIG
sed -i "s/AuthPort = .*/AuthPort = ${OG_PORT}551/" $GCONFIG
sed -i "s/ListenAddr = .*/ListenAddr = \":${OG_PORT}303\"/" $GCONFIG
sed -i "s/DiscAddr = .*/DiscAddr = \":${OG_PORT}303\"/" $GCONFIG
sed -i "s/^# *Port = .*/# Port = ${OG_PORT}901/" $GCONFIG
sed -i "s/^# *InfluxDBEndpoint = .*/# InfluxDBEndpoint = \"http:\/\/localhost:${OG_PORT}086\"/" $GCONFIG

# ==== SYSTEMD SERVICES ====
# Consensus service file (branch on NODE_TYPE)
if [ "$NODE_TYPE" = "validator" ]; then
sudo tee /etc/systemd/system/${OG_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0gchaind Node Service - ${OG_SERVICE_NAME} (Validator)
After=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=testnet
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \\
  --chaincfg.chain-spec testnet \\
  --chaincfg.restaking.enabled \\
  --chaincfg.restaking.symbiotic-rpc-dial-url ${ETH_RPC_URL} \\
  --chaincfg.restaking.symbiotic-get-logs-block-range ${BLOCK_NUM} \\
  --home $HOME/.0gchaind/0g-home/0gchaind-home \\
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/kzg-trusted-setup.json \\
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/jwt.hex \\
  --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \\
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \\
  --p2p.external_address=${EXTERNAL_IP}:${OG_PORT}656
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
else
sudo tee /etc/systemd/system/${OG_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0gchaind Node Service - ${OG_SERVICE_NAME} (RPC)
After=network-online.target

[Service]
User=$USER
Environment=CHAIN_SPEC=testnet
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0gchaind start \\
  --chaincfg.chain-spec testnet \\
  --home $HOME/.0gchaind/0g-home/0gchaind-home \\
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/kzg-trusted-setup.json \\
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/jwt.hex \\
  --chaincfg.kzg.implementation=crate-crypto/go-kzg-4844 \\
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \\
  --p2p.external_address=${EXTERNAL_IP}:${OG_PORT}656
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
fi

# Geth service file
sudo tee /etc/systemd/system/${OG_GETH_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=0g Geth Node Service - ${OG_GETH_SERVICE_NAME}
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/.0gchaind
ExecStart=$HOME/go/bin/0g-geth \\
  --config $HOME/.0gchaind/geth-config.toml \\
  --datadir $HOME/.0gchaind/0g-home/geth-home \\
  --http.port ${OG_PORT}545 \\
  --ws.port ${OG_PORT}546 \\
  --authrpc.port ${OG_PORT}551 \\
  --port ${OG_PORT}303 \\
  --discovery.port ${OG_PORT}303 \\
  --networkid 16602
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# ==== START SERVICES ====
sudo systemctl daemon-reload
sudo systemctl enable ${OG_SERVICE_NAME}
sudo systemctl enable ${OG_GETH_SERVICE_NAME}
sudo systemctl start ${OG_SERVICE_NAME}
sudo systemctl start ${OG_GETH_SERVICE_NAME}

# ==== DONE ====
echo -e "\n${GREEN}? 0G Node Installation Completed Successfully!${RESET}"
echo -e "\n${YELLOW}Node Configuration Summary:${RESET}"
echo -e "Type: ${CYAN}$NODE_TYPE${RESET}"
echo -e "Moniker: ${CYAN}$MONIKER${RESET}"
echo -e "Port Prefix: ${CYAN}$OG_PORT${RESET}"
echo -e "Consensus Service: ${CYAN}${OG_SERVICE_NAME}.service${RESET}"
echo -e "Geth Service: ${CYAN}${OG_GETH_SERVICE_NAME}.service${RESET}"
echo -e "Indexer: ${CYAN}$([ "$ENABLE_INDEXER" = "yes" ] && echo "Enabled" || echo "Disabled")${RESET}"
[ "$NODE_TYPE" = "validator" ] && echo -e "ETH_RPC_URL: ${CYAN}$ETH_RPC_URL${RESET}\nBLOCK_NUM: ${CYAN}$BLOCK_NUM${RESET}"
echo -e "Node ID: ${CYAN}$(0gchaind comet show-node-id --home $HOME/.0gchaind/0g-home/0gchaind-home/)${RESET}"
echo -e "\nTo view logs: sudo journalctl -u ${OG_SERVICE_NAME} -u ${OG_GETH_SERVICE_NAME} -fn 100"
echo -e "\n${YELLOW}Press Enter to continue to main menu...${RESET}"
read -r
