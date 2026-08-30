#!/bin/bash

set -euo pipefail

cat >&2 <<'MSG'
Newton deployment is intentionally disabled in the current Valley of 0G Testnet toolkit.

Newton used the historical EVM chain ID 16600. Valley now manages the current
Galileo testnet, whose EVM chain ID is 16602. Reusing the old Newton installer
would bypass the current network-identity and release-safety contract.

Use the Galileo deployment path instead. Historical Newton material remains in
Git history for reference, but it is not an executable supported workflow.
MSG
exit 2
