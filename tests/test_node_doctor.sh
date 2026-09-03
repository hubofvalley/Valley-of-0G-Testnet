#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DOCTOR="$ROOT/resources/vo0g_node_doctor.sh"
MAIN="$ROOT/resources/valleyof0G.sh"

fail() { echo "NODE_DOCTOR_TEST_FAIL: $*" >&2; exit 1; }

bash "$DOCTOR" --version | grep -Fq 'Valley of 0G Node Doctor (Testnet) 1.0.0' || fail "version output changed unexpectedly"
if grep -Eq 'systemctl[[:space:]]+(start|stop|restart|enable|disable)|sed[[:space:]]+-i|cast[[:space:]]+send|--private-key' "$DOCTOR"; then
    fail "doctor contains a mutating or signing command"
fi

tmp_home=$(mktemp -d)
trap 'rm -rf "$tmp_home"' EXIT
set +e
json_out=$(HOME="$tmp_home" \
    VALLEY_MANIFEST_PATH="$ROOT/VERSIONS.json" \
    VO0G_CONSENSUS_RPC="http://127.0.0.1:9" \
    VO0G_EVM_RPC="http://127.0.0.1:9" \
    VO0G_PUBLIC_EVM_RPC="http://127.0.0.1:9" \
    bash "$DOCTOR" --json)
rc=$?
set -e
[ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] || fail "doctor returned unexpected exit code $rc"
printf '%s\n' "$json_out" | jq -e '.network == "testnet" and .expected_chain_id == 16602 and (.results | type == "array")' >/dev/null || fail "invalid doctor JSON contract"

doctor_dispatch_line=$(grep -n 'if \[ "${1:-}" = "doctor" \]' "$MAIN" | head -n1 | cut -d: -f1)
profile_source_line=$(grep -n '^source "\$HOME/.bash_profile"' "$MAIN" | head -n1 | cut -d: -f1)
[ -n "$doctor_dispatch_line" ] && [ -n "$profile_source_line" ] || fail "could not locate doctor dispatch/profile source"
[ "$doctor_dispatch_line" -lt "$profile_source_line" ] || fail "doctor dispatch must run before interactive profile/prompt path"

echo "NODE_DOCTOR_TEST_OK"
