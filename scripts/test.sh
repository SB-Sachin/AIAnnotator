#!/bin/zsh
# Command Line Tools don't wire up the Swift Testing macro plugin; point the compiler at it.
# Set OLLAMA_E2E=1 to also run the end-to-end test against a running Ollama.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
