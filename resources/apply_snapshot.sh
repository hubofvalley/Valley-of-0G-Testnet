#!/bin/bash

set -euo pipefail

cat >&2 <<'MSG'
Galileo snapshot application is intentionally disabled in Valley of 0G Testnet.

The current managed Galileo EVM chain ID is 16602. The snapshot provider/path
previously configured by this repository has not yet been independently pinned
with chain-specific metadata proving that its archives belong to the current
16602 network.

Use normal P2P sync for now. Re-enable this helper only after the provider,
chain identity, archive layout, height metadata, and integrity verification
have been reviewed and pinned in VERSIONS.json.
MSG
exit 2
