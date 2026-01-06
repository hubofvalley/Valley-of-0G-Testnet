#!/bin/bash

function update_version {
    VERSION=$1
    RELEASE_URL="$2/galileo-${VERSION}.tar.gz"
    BACKUP_DIR="$HOME/backups"
    
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

 
    echo "Updating to version $VERSION..."
    
    # Stop services
    sudo systemctl stop 0g-geth.service || { echo "Failed to stop 0g-geth"; exit 1; }
    sudo systemctl stop 0gchaind.service || { echo "Failed to stop 0gchaind"; exit 1; }
 
    # Backup old binaries
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    mkdir -p $BACKUP_DIR
    [ -f $HOME/go/bin/0g-geth ] && cp $HOME/go/bin/0g-geth $BACKUP_DIR/0g-geth.$TIMESTAMP
    [ -f $HOME/go/bin/0gchaind ] && cp $HOME/go/bin/0gchaind $BACKUP_DIR/0gchaind.$TIMESTAMP
 
    # Download and install new version
    cd $HOME
    wget $RELEASE_URL || { echo "Download failed"; exit 1; }
    tar -xzf galileo-${VERSION}.tar.gz || { echo "Extraction failed"; exit 1; }
    rm galileo-${VERSION}.tar.gz
 
    cp galileo-${VERSION}/$NODE_TYPE/bin/geth $HOME/go/bin/0g-geth
    cp galileo-${VERSION}/$NODE_TYPE/bin/0gchaind $HOME/go/bin/0gchaind
    sudo chmod +x $HOME/go/bin/0g-geth
    sudo chmod +x $HOME/go/bin/0gchaind

    # Restart services
    sudo systemctl daemon-reload
    sudo systemctl start 0g-geth.service || { echo "Failed to start 0g-geth"; exit 1; }
    sudo systemctl start 0gchaind.service || { echo "Failed to start 0gchaind"; exit 1; }

    echo "Update to 0gchain-Galileo $VERSION completed!"
}

BASE_URL="https://github.com/0gfoundation/0gchain-NG/releases/download"

# Display menu
echo "Select version to update:"
echo "a) v3.0.2"
echo "b) v3.0.3"
echo "c) v3.0.4 (Latest version)"

read -p "Enter the letter corresponding to the version: " choice

read -p "Are you sure you want to proceed with the update? (yes/no): " confirm
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
if [[ "$confirm" != "yes" ]]; then
    echo "Update cancelled."
    exit 0
fi

case $choice in
    a)
        update_version "v3.0.2" "$BASE_URL/3.0.2"
        ;;
    b)
        update_version "v3.0.3" "$BASE_URL/3.0.3"
        ;;
    c)
        update_version "v3.0.4" "$BASE_URL/3.0.4"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Let's Buidl 0G Together!"

