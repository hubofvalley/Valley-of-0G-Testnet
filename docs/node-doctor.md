# Valley of 0G Testnet Node Doctor

Node Doctor is a read-only health and configuration-drift inspector for a Valley of 0G Galileo testnet node.

It does not edit configuration, restart services, replace binaries, change firewall rules, submit transactions, or read/modify validator or wallet private keys.

## Run

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/valleyof0G.sh) doctor
```

Machine-readable output:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/valleyof0G.sh) doctor --json
```

Treat warnings as non-zero as well:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/valleyof0G.sh) doctor --strict
```

## Checks

The doctor checks the managed manifest, RPC dependencies, local consensus state, local and public EVM chain ID `16602`, CL/EL height gap when both endpoints are available, expected service state, consensus RPC exposure, NTP status, disk headroom, and managed/upstream version drift recorded in `VERSIONS.json`.

The current managed validator target is deliberately separate from the upstream-latest field. A newer upstream release is advisory until its upgrade path is reviewed.

## Exit codes

- `0`: no `FAIL` results; warnings are allowed in normal mode.
- `1`: one or more `FAIL` results, or any warning when `--strict` is used.
- `2`: invalid command-line input or missing requirements for the requested output mode.

Node Doctor is diagnostic only. Review remediation before changing a validator or storage service.
