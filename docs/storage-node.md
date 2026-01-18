# Storage Node Guide

Deploy and manage a 0G storage node on Galileo testnet.

## System Requirements

| Category | Requirements |
|----------|--------------|
| CPU | 8+ cores |
| RAM | 32+ GB |
| Storage | 500GB-1TB NVMe SSD |
| Bandwidth | 100 MBit/s |

## Installation

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Testnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
   ```
2. Select **"Storage Node"** → **"Deploy Storage Node"**
3. Follow the interactive prompts

## Contract Types

| Type | Contract Address |
|------|------------------|
| Standard | `0x1785c8683b3c527618eFfF78d876d9dCB4b70285` |
| Turbo | `0x3A0d1d67497Ad770d6f72e7f4B8F0BAbaa2A649C` |

## Updating

1. Launch Valley of 0G
2. Select **"Storage Node"** → **"Update Storage Node"**

## Service Management

| Action | Menu Path |
|--------|-----------|
| Show status | **"Storage Node"** → **"Show Storage Status"** |
| Show logs | **"Storage Node"** → **"Show Storage Logs"** |
| Restart | **"Storage Node"** → **"Restart Storage Node"** |
| Stop | **"Storage Node"** → **"Stop Storage Node"** |
| Delete | **"Storage Node"** → **"Delete Storage Node"** |

## Configuration Changes

1. Launch Valley of 0G
2. Select **"Storage Node"** → **"Change Storage Node Configuration"**

## Snapshot

1. Launch Valley of 0G
2. Select **"Storage Node"** → **"Apply Storage Node Snapshot"**
3. Choose Turbo or Standard contract snapshot

> ⚠️ **Note**: Snapshots contain `flow_db` only. Your `data_db` will auto-create on start. Never use pre-made `data_db` - it would mine for someone else's wallet!

## Related Documentation

- [Validator Node Guide](validator-node.md)
- [Storage KV Guide](storage-kv.md)
