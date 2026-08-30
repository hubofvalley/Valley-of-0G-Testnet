#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MAIN="$ROOT/resources/valleyof0G.sh"

fail() { echo "RUNTIME_SCRIPT_PIN_TEST_FAIL: $*" >&2; exit 1; }

runtime_ref=$(sed -n 's/^readonly VALLEY_RUNTIME_REF="\([0-9a-f]\{40\}\)"$/\1/p' "$MAIN")
[ -n "$runtime_ref" ] || fail "VALLEY_RUNTIME_REF must be a full 40-character Git commit SHA"
grep -Fq 'run_repository_script()' "$MAIN" || fail "immutable helper dispatcher is missing"
grep -Fq '${VALLEY_REPOSITORY}/${VALLEY_RUNTIME_REF}/${relative_path}' "$MAIN" || fail "remote helper fetch is not pinned"

if grep -Fq 'raw.githubusercontent.com/hubofvalley/Valley-of-0G-Testnet/main/resources/' "$MAIN"; then
    fail "executable runtime helper still loads from mutable main"
fi

expected_helpers=(
  resources/0g_validator_node_galileo_install.sh
  resources/0g_validator_node_update_manual.sh
  resources/apply_snapshot.sh
  resources/0g_storage_node_install.sh
  resources/0g_storage_node_update.sh
  resources/0g_turbo_zgs_node_snapshot.sh
  resources/0g_storage_node_change.sh
  resources/0g_storage_kv_install.sh
  resources/0g_storage_kv_update.sh
)
for helper in "${expected_helpers[@]}"; do
    grep -Fq "run_repository_script $helper" "$MAIN" || fail "menu helper is not dispatched immutably: $helper"
done

echo "RUNTIME_SCRIPT_PIN_TEST_OK"
