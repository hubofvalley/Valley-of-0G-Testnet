<p align="center">
  <img src="resources/image_vo0g_menu.png" alt="Valley of 0G Logo" width="500">
</p>

<h1 align="center">Valley of 0G Testnet</h1>

<p align="center">
  <strong>A comprehensive toolkit for deploying and managing 0G validator and storage nodes on Galileo testnet</strong>
</p>

<p align="center">
  <a href="https://0g.ai" target="_blank">0G Labs</a> •
  <a href="https://docs.0g.ai" target="_blank">Official Docs</a> •
  <a href="https://github.com/hubofvalley" target="_blank">Grand Valley</a>
</p>

---

## 🚀 Overview

Valley of 0G Testnet is an open-source project by **Grand Valley** that provides automated scripts for deploying and managing 0G validator nodes and storage infrastructure on the **Galileo testnet**.

## 📋 System Requirements

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

## ⚡ Quick Start

Run the main interactive menu:

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Testnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
```

## 📦 Features

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

## 🔧 Current Versions

| Component | Version |
|-----------|---------|
| Validator Node | v3.0.3 |
| Storage Node | v1.1.0 |
| Storage KV | v1.4.0 |
| Chain | 0gchain-16601 (Galileo) |

## 🌐 Grand Valley Public Endpoints

| Type | URL |
|------|-----|
| Cosmos RPC | `https://lightnode-rpc-0g.grandvalleys.com` |
| EVM RPC | `https://lightnode-json-rpc-0g.grandvalleys.com` |
| Cosmos REST API | `https://lightnode-api-0g.grandvalleys.com` |
| Peer | `a97c8615903e795135066842e5739e30d64e2342@peer-0g.grandvalleys.com:28656` |
| Explorer | `https://explorer.grandvalleys.com` |

## 🔐 Privacy & Security

- **No external data storage** - All operations run locally
- **No phishing links** - All URLs are for legitimate 0G operations
- **Open source** - Full audit trail available

## 📖 Documentation

For detailed documentation, see the [docs/](docs/) folder.

## 🔗 Links

**0G Labs:**
- [Website](https://0g.ai) | [Docs](https://docs.0g.ai) | [X/Twitter](https://x.com/0G_labs)

**Grand Valley:**
- [GitHub](https://github.com/hubofvalley) | [X/Twitter](https://x.com/bacvalley) | [Testnet Guide](https://github.com/hubofvalley/Testnet-Guides/tree/main/0g%20(zero-gravity))

## 📧 Contact

Email: letsbuidltogether@grandvalleys.com

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
