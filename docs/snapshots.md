# Snapshots Guide

Apply snapshots for faster node synchronization on Galileo testnet.

## Validator Node Snapshot

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Testnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
   ```
2. Select **"Validator Node"** → **"Apply Snapshot"**
3. Follow the prompts

## Storage Node Snapshot

1. Launch Valley of 0G
2. Select **"Storage Node"** → **"Apply Storage Node Snapshot"**
3. Choose contract type:
   - **Standard Contract** - Not currently available
   - **Turbo Contract** - Available

### Important Notes

> ⚠️ **Security Warning**:
> - Snapshots contain `flow_db` (blockchain data) only
> - `data_db` (mining storage) will auto-create when node starts
> - **Never use pre-made `data_db`** - it would mine for someone else's wallet!

### Post-Snapshot Downtime

After applying a snapshot, your storage node will experience several hours of downtime while the `data_db` automatically syncs. This is normal behavior - no action needed.

## Related Documentation

- [Validator Node Guide](validator-node.md)
- [Storage Node Guide](storage-node.md)
