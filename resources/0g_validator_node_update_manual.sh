#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source "$HOME/.bash_profile" 2>/dev/null || true

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MANIFEST="${VALLEY_MANIFEST_PATH:-$SCRIPT_DIR/../VERSIONS.json}"
command -v jq >/dev/null 2>&1 || { echo "jq is required to read VERSIONS.json." >&2; exit 2; }
[ -r "$MANIFEST" ] || { echo "VERSIONS.json is required: $MANIFEST" >&2; exit 2; }

manifest_get() {
    jq -er "$1 | select(. != null and . != \"\")" "$MANIFEST" 2>/dev/null
}

MANAGED_VERSION=$(manifest_get '.components.validator.bundle.version_current')
RELEASE_REF=$(manifest_get '.components.validator.bundle.release_ref')
RELEASE_REPO=$(manifest_get '.components.validator.bundle.release_repo')
RELEASE_ARTIFACT=$(manifest_get '.components.validator.bundle.release_artifact')
RELEASE_SHA256=$(manifest_get '.components.validator.bundle.release_artifact_sha256')
EXPECTED_CHAIN_ID=$(manifest_get '.chain.evm_chain_id')
RELEASE_URL="${RELEASE_REPO}/releases/download/${RELEASE_REF}/${RELEASE_ARTIFACT}"
EXTRACT_DIR="galileo-${MANAGED_VERSION}"

OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
EXEC_CLIENT=${EXEC_CLIENT:-geth}
case "$EXEC_CLIENT" in
    geth) EL_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}; EL_BINARY="$HOME/go/bin/0g-geth" ;;
    reth) EL_SERVICE_NAME=${OG_RETH_SERVICE_NAME:-0g-reth}; EL_BINARY="$HOME/go/bin/0g-reth" ;;
    *) echo "Update blocked: EXEC_CLIENT must be geth or reth; found $EXEC_CLIENT." >&2; exit 1 ;;
esac

[[ "$OG_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "Invalid consensus service name." >&2; exit 1; }
[[ "$EL_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "Invalid execution service name." >&2; exit 1; }
[ -x "$HOME/go/bin/0gchaind" ] && [ -x "$EL_BINARY" ] || { echo "Existing managed binaries not found; use redeploy instead." >&2; exit 1; }

for svc in "$OG_SERVICE_NAME" "$EL_SERVICE_NAME"; do
    fragment=$(systemctl show "$svc" -p FragmentPath --value 2>/dev/null || true)
    [ -n "$fragment" ] && [ -f "$fragment" ] || { echo "Update blocked: $svc.service not found." >&2; exit 1; }
    unit_user=$(sed -n 's/^User=//p' "$fragment" | tail -n 1)
    unit_workdir=$(sed -n 's/^WorkingDirectory=//p' "$fragment" | tail -n 1)
    if [ "$unit_user" != "$(id -un)" ] || [ "$unit_workdir" != "$HOME/.0gchaind" ]; then
        echo "Update blocked: $svc.service belongs to another instance." >&2
        exit 1
    fi
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
archive="$tmpdir/$RELEASE_ARTIFACT"

echo "Downloading and verifying Galileo $MANAGED_VERSION while services remain online..."
curl -fL --retry 3 "$RELEASE_URL" -o "$archive"
printf '%s  %s\n' "$RELEASE_SHA256" "$archive" | sha256sum --check
tar -xzf "$archive" -C "$tmpdir"
staged_root="$tmpdir/$EXTRACT_DIR/bin"
[ -x "$staged_root/0gchaind" ] || { echo "Verified archive is missing bin/0gchaind." >&2; exit 1; }
if [ "$EXEC_CLIENT" = "geth" ]; then
    STAGED_EL="$staged_root/geth"
else
    STAGED_EL="$staged_root/reth"
fi
[ -x "$STAGED_EL" ] || { echo "Verified archive is missing the selected $EXEC_CLIENT binary." >&2; exit 1; }

if [ "$EXEC_CLIENT" = "geth" ]; then
    GCONFIG="$HOME/.0gchaind/geth-config.toml"
    [ -f "$GCONFIG" ] || { echo "Missing $GCONFIG; use redeploy instead." >&2; exit 1; }
    grep -Eq '^OverrideStakingActivation[[:space:]]*=[[:space:]]*1767830400$' "$GCONFIG" || {
        echo "Existing Geth config lacks Galileo staking activation; update blocked before downtime." >&2
        exit 1
    }
fi

echo "Execution client will remain $EXEC_CLIENT. This update does not combine a Geth<->Reth migration with the bundle upgrade."
read -r -p "Type UPDATE-GALILEO to begin the downtime window: " confirm
[ "$confirm" = "UPDATE-GALILEO" ] || { echo "Update cancelled before services were stopped."; exit 0; }

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$HOME/backups/valley-0g-testnet/$timestamp"
mkdir -p "$backup"
chmod 700 "$backup"
cp "$HOME/go/bin/0gchaind" "$backup/0gchaind"
cp "$EL_BINARY" "$backup/$(basename "$EL_BINARY")"

service_stopped=0
success=0
rollback() {
    [ "$service_stopped" -eq 1 ] || return 0
    echo "Galileo update failed after downtime began; restoring previous binaries." >&2
    install -m 0755 "$backup/0gchaind" "$HOME/go/bin/0gchaind" 2>/dev/null || true
    install -m 0755 "$backup/$(basename "$EL_BINARY")" "$EL_BINARY" 2>/dev/null || true
    sudo systemctl restart "$EL_SERVICE_NAME" 2>/dev/null || true
    sudo systemctl restart "$OG_SERVICE_NAME" 2>/dev/null || true
}
finish() {
    local rc=$?
    [ "$success" -eq 1 ] || rollback
    rm -rf "$tmpdir"
    return "$rc"
}
trap finish EXIT

service_stopped=1
sudo systemctl stop "$OG_SERVICE_NAME"
sudo systemctl stop "$EL_SERVICE_NAME"
install -m 0755 "$staged_root/0gchaind" "$HOME/go/bin/0gchaind"
install -m 0755 "$STAGED_EL" "$EL_BINARY"
sudo systemctl restart "$EL_SERVICE_NAME"
if [ "$EXEC_CLIENT" = "reth" ]; then
    engine_port=${OG_PORT:-26}551
    engine_ready=no
    for _ in $(seq 1 30); do
        if ss -lnt 2>/dev/null | grep -q ":${engine_port}[[:space:]]"; then
            engine_ready=yes
            break
        fi
        sleep 1
    done
    [ "$engine_ready" = "yes" ] || { echo "Reth Engine API did not become ready; triggering rollback before consensus restart." >&2; exit 1; }
fi
sudo systemctl restart "$OG_SERVICE_NAME"
sleep 2
systemctl is-active --quiet "$EL_SERVICE_NAME"
systemctl is-active --quiet "$OG_SERVICE_NAME"

rpc_port=${OG_PORT:-26}545
chain_hex=$(curl -fsS --connect-timeout 3 --max-time 6 -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "http://127.0.0.1:${rpc_port}" 2>/dev/null | jq -r '.result // empty' || true)
if [[ "$chain_hex" =~ ^0x[0-9a-fA-F]+$ ]]; then chain_dec=$((16#${chain_hex#0x})); else chain_dec=""; fi
[ "$chain_dec" = "$EXPECTED_CHAIN_ID" ] || { echo "Post-update local chain verification failed." >&2; exit 1; }

success=1
service_stopped=0
echo "Galileo $MANAGED_VERSION update completed with $EXEC_CLIENT preserved. Backup retained at: $backup"
