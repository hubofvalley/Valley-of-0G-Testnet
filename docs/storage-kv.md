# Storage KV Guide

Deploy and manage 0G Storage KV service on Galileo testnet.

## Overview

Storage KV provides key-value storage service that works with the 0G storage infrastructure.

## System Requirements

| Category | Requirements |
|----------|--------------|
| CPU | 8+ cores |
| RAM | 32+ GB |
| Storage | Matches the size of KV streams it maintains |

## Installation

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Testnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
   ```
2. Select **"Storage KV"** → **"Deploy Storage KV"**
3. Follow the interactive prompts

## Updating

1. Launch Valley of 0G
2. Select **"Storage KV"** → **"Update Storage KV"**

## Service Management

| Action | Menu Path |
|--------|-----------|
| Show status | **"Storage KV"** → **"Show Storage KV Status"** |
| Show logs | **"Storage KV"** → **"Show Storage KV Logs"** |
| Restart | **"Storage KV"** → **"Restart Storage KV"** |
| Stop | **"Storage KV"** → **"Stop Storage KV"** |
| Delete | **"Storage KV"** → **"Delete Storage KV"** |

## Related Documentation

- [Storage Node Guide](storage-node.md)
- [Validator Node Guide](validator-node.md)
