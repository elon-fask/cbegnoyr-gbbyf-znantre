#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

NODE_VERSION="v22.17.1"
GOINFRE="/goinfre/$USER"
NODE_DIR="$GOINFRE/node"
PROJECT_DIR="$GOINFRE/projects/dsh-our-free-model"
DATA_DIR="$GOINFRE/our-free-model-data"
KEY_FILE="$DATA_DIR/.api_key"
SETTINGS_FILE="$DATA_DIR/settings.json"
DEFAULT_PORT="18900"
REPO_URL="https://github.com/Ebony-Vinyl/dsh-our-free-model.git"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m' RESET=$'\033[0m'
  GREEN=$'\033[32m' RED=$'\033[31m' YELLOW=$'\033[33m' CYAN=$'\033[36m'
else
  BOLD= RESET= GREEN= RED= YELLOW= CYAN=
fi
info() { printf "${CYAN}[INFO]${RESET} %s\n" "$*"; }
ok() { printf "${GREEN}[ OK ]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
fail() {
  printf "${RED}[FAIL]${RESET} %s\n" "$*" >&2
  exit 1
}

PORT="$DEFAULT_PORT"
ACTION="run"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --stop)
    ACTION="stop"
    shift
    ;;
  --status)
    ACTION="status"
    shift
    ;;
  --show-key)
    ACTION="show-key"
    shift
    ;;
  --show-login)
    ACTION="show-login"
    shift
    ;;
  --port)
    PORT="${2:?--port needs a value}"
    shift 2
    ;;
  --reset-key)
    ACTION="reset-key"
    shift
    ;;
  --reinstall-node)
    rm -rf "$NODE_DIR"
    shift
    ;;
  -h | --help)
    sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) fail "Unknown option: $1" ;;
  esac
done

port_in_use() { ss -tln 2>/dev/null | grep -qE ":${PORT}\b"; }

[[ -d /goinfre ]] || fail "/goinfre does not exist on this workstation"
mkdir -p "$GOINFRE" "$DATA_DIR"

# Read a field from settings.json — no jq/python dependency
read_field() {
  local field="$1"
  [[ -f "$SETTINGS_FILE" ]] || return 1
  "$NODE_DIR/bin/node" -e '
        const fs = require("node:fs");
        const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const v = s[process.argv[2]];
        if (typeof v === "string" && v.trim()) process.stdout.write(v);
    ' "$SETTINGS_FILE" "$field" 2>/dev/null
}

# ─── Short-circuit actions ───
case "$ACTION" in
stop)
  port_in_use || {
    ok "No service on port $PORT"
    exit 0
  }
  fuser -k "${PORT}/tcp" 2>/dev/null ||
    lsof -ti ":${PORT}" 2>/dev/null | xargs -r kill 2>/dev/null || true
  sleep 1
  port_in_use && fail "Still up — try: kill -9 \$(lsof -ti :$PORT)"
  ok "Stopped"
  exit 0
  ;;
status)
  port_in_use && ok "Service RUNNING on port $PORT" || warn "Service NOT running"
  fk=$(read_field forwardKey || true)
  [[ -n "$fk" ]] && ok "forwardKey stored (…${fk: -8})" || warn "forwardKey NOT set"
  exit 0
  ;;
show-key)
  fk=$(read_field forwardKey || true)
  [[ -n "$fk" ]] && printf '%s\n' "$fk" || {
    warn "No forwardKey in $SETTINGS_FILE"
    exit 1
  }
  exit 0
  ;;
show-login)
  mk=$(read_field managementKey || true)
  [[ -n "$mk" ]] && printf 'http://127.0.0.1:%s/#login=%s\n' "$PORT" "$mk" ||
    {
      warn "No managementKey in $SETTINGS_FILE"
      exit 1
    }
  exit 0
  ;;
reset-key)
  rm -f "$KEY_FILE"
  ok "Local .api_key cleared — next run will prompt again"
  exit 0
  ;;
esac

# ─── Step 1: Node 22 ───
if [[ -x "$NODE_DIR/bin/node" ]]; then
  installed=$("$NODE_DIR/bin/node" --version 2>/dev/null || echo "")
  major=$(printf '%s' "$installed" | sed 's/^v\([0-9]*\).*/\1/')
  if [[ "$major" =~ ^[0-9]+$ ]] && ((major >= 22)); then
    ok "Node $installed already installed"
  else
    warn "Node at $NODE_DIR is '$installed' — reinstalling"
    rm -rf "$NODE_DIR"
  fi
fi
if [[ ! -x "$NODE_DIR/bin/node" ]]; then
  info "Installing Node $NODE_VERSION → $NODE_DIR"
  mkdir -p "$NODE_DIR"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  tarball="node-${NODE_VERSION}-linux-x64.tar.xz"
  wget -q -O "$tmp/$tarball" \
    "https://nodejs.org/dist/${NODE_VERSION}/${tarball}" ||
    fail "Download failed — check network"
  tar -xJf "$tmp/$tarball" -C "$NODE_DIR" --strip-components=1 ||
    fail "Extraction failed"
  "$NODE_DIR/bin/node" --version >/dev/null || fail "Node binary won't execute"
  ok "Node $NODE_VERSION installed"
fi
export PATH="$NODE_DIR/bin:$PATH"
hash -r 2>/dev/null || true

# ─── Step 2: Data dir (no symlink) ───
[[ -L "$HOME/.our-free-model" ]] &&
  [[ "$(readlink "$HOME/.our-free-model")" == "$DATA_DIR" ]] &&
  {
    warn "Removing legacy symlink"
    rm -f "$HOME/.our-free-model"
  }
ok "Data dir: $DATA_DIR"

# ─── Step 3: Project ───
if [[ ! -d "$PROJECT_DIR/.git" ]]; then
  info "Cloning project → $PROJECT_DIR"
  mkdir -p "$(dirname "$PROJECT_DIR")"
  git clone "$REPO_URL" "$PROJECT_DIR" || fail "git clone failed"
  ok "Project cloned"
else
  ok "Project already at $PROJECT_DIR"
fi
cd "$PROJECT_DIR"
if [[ ! -d node_modules ]]; then
  info "Installing npm dependencies (first run)"
  npm install || fail "npm install failed"
  ok "Dependencies installed"
else
  ok "Dependencies already installed"
fi
port_in_use && fail "Port $PORT in use — run with --stop"

# ─── Step 3.5: API key management ───
# The service stores its own keys as `forwardKey` and `managementKey` in
# settings.json. We never overwrite `managementKey` (the service manages it).
# We only inject `forwardKey` if the user pastes one AND the service hasn't
# already set one — so we never fight the service.
manage_api_key() {
  local fk
  fk=$(read_field forwardKey || true)

  echo
  if [[ -n "$fk" ]]; then
    ok "forwardKey already set (…${fk: -8})"
    read -rp "Replace it? The service will regenerate its own on next startup. [y/N] " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      ok "Keeping existing key"
      return 0
    fi
    info "Note: replacing only takes effect if the service re-reads the file."
    info "Safest path: delete settings.json, let the service regenerate it,"
    info "then set the new forwardKey via the management URL."
    read -rp "Continue anyway? [y/N] " ans2
    [[ "$ans2" =~ ^[Yy]$ ]] || {
      ok "Aborted — keeping existing key"
      return 0
    }
  else
    info "No forwardKey yet. Paste one below, or press Enter to skip."
    info "If you skip, set it via the management URL after startup."
  fi

  local new_key=""
  read -rsp "forwardKey (or Enter to skip): " new_key
  echo
  [[ -z "$new_key" ]] && {
    warn "Skipping"
    return 0
  }

  printf '%s' "$new_key" >"$KEY_FILE"
  chmod 600 "$KEY_FILE"
  ok "Saved to $KEY_FILE (portable backup)"
  ok "The service will pick this up on next startup if settings.json is absent."
  if [[ -f "$SETTINGS_FILE" ]]; then
    warn "settings.json exists — the service's own forwardKey wins."
    warn "To apply the new key, either:"
    warn "  • delete $SETTINGS_FILE and restart, OR"
    warn "  • open the management URL and paste the key there."
  fi
}
manage_api_key

# ─── Step 4: Launch ───
export OFM_HOME="$DATA_DIR"

echo
printf "${BOLD}dsh-our-free-model standalone — launching${RESET}\n"
echo "  Node:    $(node --version)"
echo "  Project: $PROJECT_DIR"
echo "  Data:    $DATA_DIR"
echo
info "After startup:"
info "  • API calls  →  http://127.0.0.1:$PORT/v1  (Authorization: Bearer <forwardKey>)"
info "  • Get key    →  $(basename "$0") --show-key"
info "  • Get login  →  $(basename "$0") --show-login"
echo

exec node packages/standalone/cli.mjs
