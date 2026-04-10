#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_DIR="$SCRIPT_DIR/dankrazer-cli"
BINARY="$CLI_DIR/dankrazer"

# Check if binary already exists and is up to date
if [ -x "$BINARY" ] && [ "$BINARY" -nt "$CLI_DIR/cmd/dankrazer/main.go" ] && [ "$BINARY" -nt "$CLI_DIR/internal/razer/device.go" ] && [ "$BINARY" -nt "$CLI_DIR/internal/razer/client.go" ]; then
    echo "dankrazer binary is up to date."
    exit 0
fi

# Check for Go
if ! command -v go >/dev/null 2>&1; then
    echo "Error: Go is required to build dankrazer-cli." >&2
    echo "Install Go from https://go.dev/dl/ or via your package manager:" >&2
    echo "  Arch: sudo pacman -S go" >&2
    echo "  Fedora: sudo dnf install golang" >&2
    echo "  Ubuntu: sudo apt install golang-go" >&2
    exit 1
fi

echo "Building dankrazer-cli..."
cd "$CLI_DIR"
go build -o dankrazer ./cmd/dankrazer/
echo "Built successfully: $BINARY"
