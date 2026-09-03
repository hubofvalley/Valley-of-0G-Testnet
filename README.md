<p align="center">
  <img src="resources/image_vo0g_menu.png" alt="Valley of 0G Logo" width="500">
</p>

<h1 align="center">Valley of 0G Testnet</h1>

<p align="center">
  <strong>Toolkit for deploying and managing 0G validator and storage nodes on Galileo testnet</strong>
</p>

<p align="center">
  <a href="https://0g.ai" target="_blank">0G Labs</a> •
  <a href="https://docs.0g.ai" target="_blank">Official Docs</a> •
  <a href="https://github.com/hubofvalley" target="_blank">Baconvalley</a>
</p>

---

## Overview

Valley of 0G Testnet is an open-source project by **Baconvalley** that provides automated scripts for deploying and managing 0G validator nodes and storage infrastructure on the **Galileo testnet**.

## System Requirements

### Validator Node
| Category | Requirements |
|----------|--------------|
| CPU | 8 cores |
| RAM | 64+ GB |
| Storage | 1+ TB NVMe SSD |
| Bandwidth | 100 MBit/s |

### Storage Node
| Category | Requirements |
|----------|--------------|
| CPU | 8+ cores |
| RAM | 32+ GB |
| Storage | 500GB-1TB NVMe SSD |
| Bandwidth | 100 MBit/s |

## Getting started

Run the main interactive menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/valleyof0G.sh)
```

Read-only health/configuration inspection is available without entering the interactive menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/valleyof0G.sh) doctor
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/valleyof0G.sh) doctor --json
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/valleyof0G.sh) doctor --strict
```

## Features

### Validator Node
- Deploy/re-deploy validator node
- Update node version
- Apply snapshot
- Add peers
- Show status and logs

### Storage Node
- Deploy/update storage node
- Apply storage snapshot (Turbo/Standard)
- Change configuration
- Show status and logs

### Storage KV
- Deploy/update Storage KV
- Show status and logs

## Current Versions

| Component | Version |
|-----------|---------|
| Validator Node | v3.0.8 (statically rebaselined; live rehearsal pending) |
| Storage Node | v1.1.0 |
| Storage KV | v1.4.0 |
| EVM Chain ID | 16602 (Galileo) |

The canonical Galileo consensus network is `0G-testnet-galileo`. Fresh validator/RPC deployments may choose **Reth** (recommended by upstream for new deployments) or **Geth**. Existing Geth nodes are upgraded in place as Geth; Valley intentionally does not combine a database migration to Reth with a bundle upgrade.

`v3.0.8` is pinned to release commit `b80e68528d544f6c719c83d9741ca584a76973e2` and archive SHA-256 `b9c008865513c06e2cf75d7e2daee27f739356a45e505e492dcffe70b90457a7`. The code path is ready for clean-host/live rehearsal, but that rehearsal is still a release gate.

## Testnet Endpoint Status

| Type | URL |
|------|-----|
| Official Galileo EVM RPC | `https://evmrpc-testnet.0g.ai` — managed chain-identity reference (`16602`) |
| Grand Valley legacy Cosmos RPC | `https://lightnode-rpc-0g.grandvalleys.com` — **needs live repair/reverification** |
| Grand Valley legacy EVM RPC | `https://lightnode-json-rpc-0g.grandvalleys.com` — **needs live repair/reverification** |
| Grand Valley legacy Cosmos REST API | `https://lightnode-api-0g.grandvalleys.com` — **needs live repair/reverification** |

The legacy Grand Valley Testnet endpoint hostnames remain documented for repair provenance, but Valley scripts must not depend on them as a trusted network-identity source until they pass live verification again.

## Privacy & Security

- **No external data storage** - All operations run locally
- **No phishing links** - All URLs are for legitimate 0G operations
- **Open source** - Full audit trail available

## Documentation

For detailed documentation, see the [docs/](docs/) folder.

## Links

**0G Labs:**
- [Website](https://0g.ai) | [Docs](https://docs.0g.ai) | [X/Twitter](https://x.com/0G_labs)

**Baconvalley:**
- [GitHub](https://github.com/hubofvalley) | [X/Twitter](https://x.com/bacvalley)

## Contact

Email: letsbuidltogether@grandvalleys.com

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
