#!/usr/bin/env bash
# ==============================================================================
# Bootstrap — one-liner installer for classmates
# Usage: curl -fsSL <raw-url>/bootstrap.sh | bash
# ==============================================================================
set -euo pipefail

USERNAME="${USERNAME:-$(whoami)}"
ROOT="${PORTABLE_TOOLS_ROOT:-/goinfre/${USERNAME}/portable_tools}"
REPO_URL="${REPO_URL:-https://github.com/YOUR_USERNAME/portable-tools-manager}"

echo "=== Portable Tools Manager — Bootstrap ==="
echo "User: $USERNAME"
echo "Root: $ROOT"
echo ""

# Safety: make sure /goinfre exists and is writable
if [ ! -d "/goinfre/${USERNAME}" ]; then
    echo "Creating /goinfre/${USERNAME} ..."
    mkdir -p "/goinfre/${USERNAME}"
fi

if ! touch "/goinfre/${USERNAME}/.write_test" 2>/dev/null; then
    echo "ERROR: Cannot write to /goinfre/${USERNAME}. Check permissions."
    exit 1
fi
rm -f "/goinfre/${USERNAME}/.write_test"

mkdir -p "$ROOT"

# Clone or download the manager
if command -v git &>/dev/null; then
    echo "Cloning manager scripts into $ROOT/manager ..."
    git clone --depth 1 "$REPO_URL" "$ROOT/manager" 2>/dev/null || {
        echo "Git clone failed, downloading scripts directly..."
        curl -fsSL "$REPO_URL/raw/main/manager.sh" -o "$ROOT/manager.sh"
        curl -fsSL "$REPO_URL/raw/main/manager.lua" -o "$ROOT/manager.lua"
    }
else
    echo "Downloading manager scripts..."
    curl -fsSL "$REPO_URL/raw/main/manager.sh" -o "$ROOT/manager.sh"
    curl -fsSL "$REPO_URL/raw/main/manager.lua" -o "$ROOT/manager.lua"
fi

chmod +x "$ROOT/manager.sh" 2>/dev/null || true
chmod +x "$ROOT/manager/manager.sh" 2>/dev/null || true

# Initialize
if [ -x "$ROOT/manager/manager.sh" ]; then
    "$ROOT/manager/manager.sh" init
elif [ -x "$ROOT/manager.sh" ]; then
    "$ROOT/manager.sh" init
fi

echo ""
echo "=== Done! ==="
echo "Add this line to your ~/.bashrc or ~/.zshrc:"
echo "  source $ROOT/env.sh"
echo ""
echo "Then install tools, e.g.:"
echo "  $ROOT/manager/manager.sh install node"
