#!/bin/bash

set -Eeuo pipefail

# shellcheck source=/dev/null
source "$HOME/.bash_profile" 2>/dev/null || true

readonly MANAGED_VERSION="v3.0.4"
readonly UPSTREAM_LATEST_REVIEWED_AT="v3.0.8"
readonly RELEASE_URL="https://github.com/0gfoundation/0gchain-NG/releases/download/v3.0.4/galileo-v3.0.4.tar.gz"
readonly RELEASE_SHA256="62455814f2f2b3ca29e97807ebf87a26ade56a7f833b1932c06e39059b915025"
readonly STAKING_ACTIVATION="1767830400"

OG_SERVICE_NAME=${OG_SERVICE_NAME:-0gchaind}
OG_GETH_SERVICE_NAME=${OG_GETH_SERVICE_NAME:-0g-geth}
BACKUP_DIR="$HOME/backups/valley-0g-testnet"
GCONFIG="$HOME/.0gchaind/geth-config.toml"

if [ -n "${SUDO_USER:-}" ]; then
    echo "Run the updater as the node OS user, not with sudo." >&2
    exit 1
fi

echo "Valley managed Galileo target: $MANAGED_VERSION"
echo "Recorded upstream latest: $UPSTREAM_LATEST_REVIEWED_AT (review required; not auto-promoted)"
echo "Older v3.0.2/v3.0.3 downgrade paths are intentionally disabled."
echo
echo "Select version to update:"
echo "c) $MANAGED_VERSION (Valley managed target)"
read -r -p "Enter c to continue or anything else to cancel: " choice
[ "$choice" = "c" ] || { echo "Update cancelled."; exit 0; }

while true; do
    read -r -p "Deploy type? (validator/rpc): " NODE_TYPE
    NODE_TYPE=$(printf '%s' "$NODE_TYPE" | tr '[:upper:]' '[:lower:]')
    [[ "$NODE_TYPE" = "validator" || "$NODE_TYPE" = "rpc" ]] && break
    echo "Please type exactly 'validator' or 'rpc'."
done

for svc in "$OG_SERVICE_NAME" "$OG_GETH_SERVICE_NAME"; do
    fragment=$(systemctl show "$svc" -p FragmentPath --value 2>/dev/null || true)
    if [ -n "$fragment" ]; then
        [ -f "$fragment" ] || { echo "Cannot inspect $svc service: $fragment" >&2; exit 1; }
        unit_user=$(sed -n 's/^User=//p' "$fragment" | tail -n 1)
        unit_workdir=$(sed -n 's/^WorkingDirectory=//p' "$fragment" | tail -n 1)
        if [ "$unit_user" != "$(id -un)" ] || [ "$unit_workdir" != "$HOME/.0gchaind" ]; then
            echo "Update blocked: $svc.service belongs to another instance." >&2
            exit 1
        fi
    fi
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
archive="$tmpdir/galileo-v3.0.4.tar.gz"

echo "Downloading and verifying $MANAGED_VERSION while services remain online..."
curl -fsSL "$RELEASE_URL" -o "$archive"
echo "$RELEASE_SHA256  $archive" | sha256sum --check
tar -xzf "$archive" -C "$tmpdir"
staged="$tmpdir/galileo-v3.0.4/$NODE_TYPE/bin"
[ -x "$staged/geth" ] && [ -x "$staged/0gchaind" ] || {
    echo "Verified archive does not contain expected $NODE_TYPE binaries." >&2
    exit 1
}

[ -f "$GCONFIG" ] || { echo "Missing $GCONFIG; use redeploy instead of updater." >&2; exit 1; }
candidate_config="$tmpdir/geth-config.toml"
cp "$GCONFIG" "$candidate_config"
if grep -Eq '^[[:space:]]*OverrideStakingActivation[[:space:]]*=' "$candidate_config"; then
    sed -i -E "s/^[[:space:]]*OverrideStakingActivation[[:space:]]*=.*/OverrideStakingActivation = $STAKING_ACTIVATION/" "$candidate_config"
else
    patched="$tmpdir/geth-config.patched.toml"
    if ! awk -v activation="$STAKING_ACTIVATION" '
      BEGIN { inserted=0 }
      /^\[[Ee][Tt][Hh]\][[:space:]]*$/ && inserted==0 {
        print
        print "OverrideStakingActivation = " activation
        inserted=1
        next
      }
      { print }
      END { if (inserted==0) exit 42 }
    ' "$candidate_config" > "$patched"; then
        echo "Could not locate [Eth] in geth-config.toml; update blocked before downtime." >&2
        exit 1
    fi
    mv "$patched" "$candidate_config"
fi

read -r -p "Type UPDATE-GALILEO to begin the downtime window: " confirm
[ "$confirm" = "UPDATE-GALILEO" ] || { echo "Update cancelled before services were stopped."; exit 0; }

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$BACKUP_DIR/$timestamp"
mkdir -p "$backup"
cp "$HOME/go/bin/0g-geth" "$backup/0g-geth"
cp "$HOME/go/bin/0gchaind" "$backup/0gchaind"
cp "$GCONFIG" "$backup/geth-config.toml"

service_stopped=0
success=0
rollback() {
    [ "$service_stopped" -eq 1 ] || return 0
    echo "Validator update failed after downtime began; restoring previous binaries/config." >&2
    cp "$backup/0g-geth" "$HOME/go/bin/0g-geth" 2>/dev/null || true
    cp "$backup/0gchaind" "$HOME/go/bin/0gchaind" 2>/dev/null || true
    cp "$backup/geth-config.toml" "$GCONFIG" 2>/dev/null || true
    sudo systemctl restart "$OG_GETH_SERVICE_NAME" 2>/dev/null || true
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
sudo systemctl stop "$OG_GETH_SERVICE_NAME"
install -m 0755 "$staged/geth" "$HOME/go/bin/0g-geth"
install -m 0755 "$staged/0gchaind" "$HOME/go/bin/0gchaind"
install -m 0600 "$candidate_config" "$GCONFIG"

sudo systemctl restart "$OG_GETH_SERVICE_NAME"
sudo systemctl restart "$OG_SERVICE_NAME"
sleep 2
systemctl is-active --quiet "$OG_GETH_SERVICE_NAME"
systemctl is-active --quiet "$OG_SERVICE_NAME"

success=1
service_stopped=0
echo "Galileo $MANAGED_VERSION update completed. Backup retained at: $backup"
