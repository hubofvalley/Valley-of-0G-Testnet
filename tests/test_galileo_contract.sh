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
[ "$(jq -r '.components.validator.bundle.version_current' "$MANIFEST")" = 'v3.0.4' ] || fail "managed validator target must be v3.0.4"
[ "$(jq -r '.components.validator.bundle.upstream_latest' "$MANIFEST")" = 'v3.0.8' ] || fail "recorded upstream latest must be v3.0.8"
[ "$(jq -r '.components.validator.bundle.upgrade_status' "$MANIFEST")" = 'review_required' ] || fail "newer upstream validator release must remain review_required"

grep -Fq 'readonly VALLEY_EXPECTED_EVM_CHAIN_ID="16602"' "$MAIN" || fail "menu chain guard constant missing"
grep -Fq '62455814f2f2b3ca29e97807ebf87a26ade56a7f833b1932c06e39059b915025' "$INSTALLER" || fail "managed release checksum missing from installer"
grep -Fq 'OverrideStakingActivation = 1767830400' "$INSTALLER" || fail "v3.0.4 staking activation config guard missing"
grep -Fq 'REDEPLOY-GALILEO' "$INSTALLER" || fail "typed redeploy confirmation missing"
grep -Fq 'priv_validator_key.json' "$INSTALLER" || fail "consensus validator key preservation path missing"
grep -Fq 'priv_validator_state.json' "$INSTALLER" || fail "double-sign state preservation path missing"
grep -Fq 'PRESERVE_VALIDATOR_IDENTITY=yes' "$INSTALLER" || fail "redeploy does not restore existing consensus identity"
grep -Fq '127.0.0.1:${OG_PORT}060' "$INSTALLER" || fail "pprof should be loopback-bound"
grep -Fq '127.0.0.1:${OG_PORT}660' "$INSTALLER" || fail "prometheus should be loopback-bound"

download_line=$(grep -n 'wget -q "$GALILEO_URL"' "$INSTALLER" | head -n1 | cut -d: -f1)
checksum_line=$(grep -n 'sha256sum --check' "$INSTALLER" | head -n1 | cut -d: -f1)
cleanup_line=$(grep -n 'sudo systemctl stop 0gchaind' "$INSTALLER" | head -n1 | cut -d: -f1)
[ "$download_line" -lt "$cleanup_line" ] && [ "$checksum_line" -lt "$cleanup_line" ] || fail "release must be downloaded and verified before destructive cleanup"

grep -Fq 'Downloading and verifying $MANAGED_VERSION while services remain online' "$UPDATER" || fail "validator updater must stage before downtime"
updater_download=$(grep -n 'curl -fsSL "$RELEASE_URL"' "$UPDATER" | head -n1 | cut -d: -f1)
updater_stop=$(grep -n 'systemctl stop "$OG_SERVICE_NAME"' "$UPDATER" | head -n1 | cut -d: -f1)
[ "$updater_download" -lt "$updater_stop" ] || fail "validator updater stops service before verified artifact is ready"
grep -Fq 'UPDATE-GALILEO' "$UPDATER" || fail "typed validator-update confirmation missing"
grep -Fq 'OverrideStakingActivation' "$UPDATER" || fail "validator updater does not enforce v3.0.4 config requirement"

grep -Fq 'Newton deployment is intentionally disabled' "$NEWTON" || fail "Newton path must fail closed"
grep -Fq 'exit 2' "$NEWTON" || fail "Newton disabled path must exit 2"
grep -Fq 'Galileo snapshot application is intentionally disabled' "$SNAPSHOT" || fail "unverified Galileo snapshot path must fail closed"
grep -Fq 'exit 2' "$SNAPSHOT" || fail "snapshot disabled path must exit 2"
grep -Fq 'Galileo Storage snapshot application is intentionally disabled' "$STORAGE_SNAPSHOT" || fail "unverified Galileo Storage snapshot must fail closed"
grep -Fq 'exit 2' "$STORAGE_SNAPSHOT" || fail "Storage snapshot disabled path must exit 2"

echo "GALILEO_CONTRACT_TEST_OK"
