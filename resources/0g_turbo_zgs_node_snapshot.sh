#!/bin/bash

set -euo pipefail

cat >&2 <<'MSG'
Galileo Storage snapshot application is intentionally disabled.

The previously configured Storage snapshot URL is shared with the mainnet
toolkit and does not currently carry pinned metadata proving that its database
belongs to the current Galileo 16602 environment. Applying it would therefore
violate Valley's network-identity safety contract.

Use normal Storage synchronization for now. Re-enable only after a Galileo-
specific provider, archive layout, integrity metadata, and compatibility with
the managed Storage Node version have been independently reviewed and pinned.
MSG
exit 2
