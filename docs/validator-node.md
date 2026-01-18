# Validator Node Guide

Deploy and manage a 0G validator node on Galileo testnet.

## System Requirements

| Category | Requirements |
|----------|--------------|
| CPU | 8 cores |
| RAM | 64+ GB |
| Storage | 1+ TB NVMe SSD |
| Bandwidth | 100 MBit/s |
| OS | Ubuntu 22.04/24.04 (recommended) |

## Installation

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Testnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
   ```
2. Select **"Validator Node"** → **"Deploy Validator Node"**
3. Follow the interactive prompts

### What Gets Installed

| Component | Details |
|-----------|---------|
| **0gchaind** | Consensus client (v3.0.3) |
| **0g-geth** | Execution client |
| **0gchaind.service** | Systemd service for consensus |
| **0g-geth.service** | Systemd service for execution |
| **Data directory** | `$HOME/.0gchaind` |

## Updating

1. Launch Valley of 0G
2. Select **"Validator Node"** → **"Manage Validator Node"** → **"Update Validator Node Version"**

## Service Management

| Action | Menu Path |
|--------|-----------|
| Show status | **"Validator Node"** → **"Show Validator Status"** |
| Show logs | **"Validator Node"** → **"Show Validator Logs"** |
| Restart | **"Validator Node"** → **"Restart Validator Node"** |
| Stop | **"Validator Node"** → **"Stop Validator Node"** |
| Delete | **"Validator Node"** → **"Delete Validator Node"** |

## Adding Peers

1. Launch Valley of 0G
2. Select **"Validator Node"** → **"Add Peers"**
3. Choose manual entry or Grand Valley's peers

## Snapshot

1. Launch Valley of 0G
2. Select **"Validator Node"** → **"Apply Snapshot"**

## Related Documentation

- [Storage Node Guide](storage-node.md)
- [Snapshots Guide](snapshots.md)
