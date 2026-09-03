#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/VERSIONS.json"

fail() { echo "DOCS_CONSISTENCY_TEST_FAIL: $*" >&2; exit 1; }

[ "$(jq -r '.chain.evm_chain_id' "$MANIFEST")" = '16602' ] || fail "manifest chain ID drift"
[ "$(jq -r '.components.validator.bundle.version_current' "$MANIFEST")" = 'v3.0.8' ] || fail "manifest managed validator drift"

if grep -RInE '0gchain-16601|EVM Chain ID[^0-9]*16601|Validator Node \| v3\.0\.3' "$ROOT/README.md" "$ROOT/docs"; then
    fail "public docs contain stale Galileo chain/version facts"
fi
if grep -RIn 'Testnet-Guides/main/0g%20' "$ROOT/README.md" "$ROOT/docs"; then
    fail "public docs still bootstrap from legacy Testnet-Guides"
fi
grep -Fq 'Valley-of-0G-Testnet/main/resources/valleyof0G.sh' "$ROOT/README.md" || fail "canonical quickstart missing"
grep -Fq 'doctor --json' "$ROOT/README.md" || fail "Node Doctor JSON usage missing"

echo "DOCS_CONSISTENCY_TEST_OK"
