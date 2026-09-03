#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/VERSIONS.json"
MAIN="$ROOT/resources/valleyof0G.sh"
INSTALLER="$ROOT/resources/0g_validator_node_galileo_install.sh"
UPDATER="$ROOT/resources/0g_validator_node_update_manual.sh"
NEWTON="$ROOT/resources/0g_validator_node_newton_install.sh"
SNAPSHOT="$ROOT/resources/apply_snapshot.sh"
STORAGE_SNAPSHOT="$ROOT/resources/0g_turbo_zgs_node_snapshot.sh"

fail() { echo "GALILEO_CONTRACT_TEST_FAIL: $*" >&2; exit 1; }

[ "$(jq -r '.chain.evm_chain_id' "$MANIFEST")" = '16602' ] || fail "manifest Galileo chain ID must be 16602"
[ "$(jq -r '.components.validator.bundle.version_current' "$MANIFEST")" = 'v3.0.8' ] || fail "managed validator target must be v3.0.8"
[ "$(jq -r '.components.validator.bundle.upstream_latest' "$MANIFEST")" = 'v3.0.8' ] || fail "recorded upstream latest must be v3.0.8"
[ "$(jq -r '.components.validator.bundle.upgrade_status' "$MANIFEST")" = 'staged_pending_live_rehearsal' ] || fail "v3.0.8 must remain gated on live rehearsal"
[ "$(jq -r '.chain.consensus_network' "$MANIFEST")" = '0G-testnet-galileo' ] || fail "Galileo consensus identity drift"
[ "$(jq -r '.components.validator.bundle.release_commit' "$MANIFEST")" = 'b80e68528d544f6c719c83d9741ca584a76973e2' ] || fail "v3.0.8 release commit drift"
[ "$(jq -r '.components.validator.execution_client.recommended_for_fresh_install' "$MANIFEST")" = 'reth' ] || fail "fresh-install execution recommendation drift"
[ "$(jq -r '.components.storage_kv.pinned_commit' "$MANIFEST")" = '707db658c80aebb9f902152b311a1c26884f9e63' ] || fail "Storage KV v1.4.0 peeled commit drift"

grep -Fq 'readonly VALLEY_EXPECTED_EVM_CHAIN_ID="16602"' "$MAIN" || fail "menu chain guard constant missing"
grep -Fq 'b9c008865513c06e2cf75d7e2daee27f739356a45e505e492dcffe70b90457a7' "$MANIFEST" || fail "managed v3.0.8 release checksum missing"
grep -Fq 'GALILEO_SHA256=$(manifest_get' "$INSTALLER" || fail "installer does not consume release digest from manifest"
grep -Fq 'archive_network=' "$INSTALLER" || fail "installer does not verify archive consensus identity"
grep -Fq 'archive_chain=' "$INSTALLER" || fail "installer does not verify archive EVM identity"
grep -Fq 'redeploy was not started' "$INSTALLER" || fail "external-IP preflight must fail before destructive redeploy"
grep -Fq 'EXEC_CLIENT=reth' "$INSTALLER" || fail "fresh installer lacks Reth selection"
grep -Fq 'bin/reth' "$INSTALLER" || fail "fresh installer does not verify packaged Reth"
grep -Fq 'bin/geth' "$INSTALLER" || fail "fresh installer does not preserve Geth support"
grep -Fq 'OverrideStakingActivation' "$INSTALLER" || fail "Geth path does not verify Galileo staking activation"
grep -Fq 'REDEPLOY-GALILEO' "$INSTALLER" || fail "typed redeploy confirmation missing"
grep -Fq 'priv_validator_key.json' "$INSTALLER" || fail "consensus validator key preservation path missing"
grep -Fq 'priv_validator_state.json' "$INSTALLER" || fail "double-sign state preservation path missing"
grep -Fq 'PRESERVE_VALIDATOR_IDENTITY=yes' "$INSTALLER" || fail "redeploy does not restore existing consensus identity"
grep -Fq '127.0.0.1:${OG_PORT}060' "$INSTALLER" || fail "pprof should be loopback-bound"
grep -Fq '127.0.0.1:${OG_PORT}660' "$INSTALLER" || fail "prometheus should be loopback-bound"

download_line=$(grep -n 'curl -fL --retry 3 "$GALILEO_URL"' "$INSTALLER" | head -n1 | cut -d: -f1)
checksum_line=$(grep -n 'sha256sum --check' "$INSTALLER" | head -n1 | cut -d: -f1)
cleanup_line=$(grep -n 'sudo systemctl stop 0gchaind' "$INSTALLER" | head -n1 | cut -d: -f1)
[ "$download_line" -lt "$cleanup_line" ] && [ "$checksum_line" -lt "$cleanup_line" ] || fail "release must be downloaded and verified before destructive cleanup"

if grep -Eq 'go[0-9.]+\.linux-amd64|golang\.org/dl' "$INSTALLER"; then
    fail "validator runtime should not install an unused mutable Go toolchain"
fi

grep -Fq 'Downloading and verifying Galileo $MANAGED_VERSION while services remain online' "$UPDATER" || fail "validator updater must stage before downtime"
updater_download=$(grep -n 'curl -fL --retry 3 "$RELEASE_URL"' "$UPDATER" | head -n1 | cut -d: -f1)
updater_stop=$(grep -n 'systemctl stop "$OG_SERVICE_NAME"' "$UPDATER" | head -n1 | cut -d: -f1)
[ "$updater_download" -lt "$updater_stop" ] || fail "validator updater stops service before verified artifact is ready"
grep -Fq 'UPDATE-GALILEO' "$UPDATER" || fail "typed validator-update confirmation missing"
grep -Fq 'Execution client will remain $EXEC_CLIENT' "$UPDATER" || fail "updater does not explicitly preserve execution client"
grep -Fq 'OverrideStakingActivation' "$UPDATER" || fail "Geth updater does not enforce Galileo staking activation"
grep -Fq 'triggering rollback before consensus restart' "$UPDATER" || fail "Reth update does not fail closed when Engine API is unavailable"

[ "$(jq -r '.endpoints.grand_valley_status' "$MANIFEST")" = 'needs_live_repair' ] || fail "legacy Grand Valley Testnet endpoints must remain gated until reverified"
if grep -Fq 'curl -sS https://lightnode-rpc-0g.grandvalleys.com/net_info' "$MAIN"; then
    fail "menu must not auto-discover peers through the currently unverified legacy RPC endpoint"
fi

grep -Fq 'Newton deployment is intentionally disabled' "$NEWTON" || fail "Newton path must fail closed"
grep -Fq 'exit 2' "$NEWTON" || fail "Newton disabled path must exit 2"
grep -Fq 'Galileo snapshot application is intentionally disabled' "$SNAPSHOT" || fail "unverified Galileo snapshot path must fail closed"
grep -Fq 'exit 2' "$SNAPSHOT" || fail "snapshot disabled path must exit 2"
grep -Fq 'Galileo Storage snapshot application is intentionally disabled' "$STORAGE_SNAPSHOT" || fail "unverified Galileo Storage snapshot must fail closed"
grep -Fq 'exit 2' "$STORAGE_SNAPSHOT" || fail "Storage snapshot disabled path must exit 2"

echo "GALILEO_CONTRACT_TEST_OK"
