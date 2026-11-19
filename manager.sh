#!/usr/bin/env bash
# ==============================================================================
# Portable Tools Manager — No Sudo / No Home Partition Bloat
# Designed for 42-style school workstations with limited /home quota
# Everything installs under /goinfre/<user>/portable_tools
# ==============================================================================
set -euo pipefail

# ---- Configuration (override via environment variables) ---------------------
USERNAME="${USERNAME:-$(whoami)}"
ROOT="${PORTABLE_TOOLS_ROOT:-/goinfre/${USERNAME}/portable_tools}"
BIN_DIR="$ROOT/bin"
SRC_DIR="$ROOT/src"
BUILD_DIR="$ROOT/build"
MANIFESTS_DIR="$ROOT/manifests"
LOGS_DIR="$ROOT/logs"
TMP_DIR="$ROOT/tmp"
CACHE_DIR="$ROOT/cache"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOGS_DIR/install_${TIMESTAMP}.log"

# ---- Colors -----------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ---- Helpers ----------------------------------------------------------------
log()     { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
info()    { log "${BLUE}ℹ  $*${NC}"; }
success() { log "${GREEN}✓  $*${NC}"; }
warn()    { log "${YELLOW}⚠  $*${NC}"; }
error()   { log "${RED}✗  $*${NC}"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

ensure_dirs() {
    mkdir -p "$BIN_DIR" "$SRC_DIR" "$BUILD_DIR" "$MANIFESTS_DIR" "$LOGS_DIR" "$TMP_DIR" "$CACHE_DIR"
}

check_mount() {
    # CRITICAL: make sure ROOT is NOT on the small /home partition
    local mount_point
    mount_point=$(df -P "$ROOT" 2>/dev/null | tail -1 | awk '{print $6}')
    if [ "$mount_point" = "/home" ] || [[ "$mount_point" == /home/* ]]; then
        error "CRITICAL: $ROOT resolves to $mount_point — this is your small /home partition!
Set PORTABLE_TOOLS_ROOT to a path under /goinfre and try again."
    fi
    if ! df -P "$ROOT" 2>/dev/null | tail -1 | awk '{print $6}' | grep -q "goinfre"; then
        warn "$ROOT is not under /goinfre (mounted at $mount_point). Continuing but double-check your quota."
    fi
}

init_manifest() {
    # $1=name $2=version $3=url $4=notes $5=uninstall_cmd (optional)
    local name="$1" version="$2" url="$3" notes="${4:-}" uninstall="${5:-rm -rf $BUILD_DIR/$name}"
    local manifest="$MANIFESTS_DIR/${name}.manifest"
    cat > "$manifest" <<EOF
# ============================================================
# Tool: $name
# Installed: $(date '+%Y-%m-%d %H:%M:%S')
# Installed by: $(whoami)@$(hostname)
# ============================================================
name=$name
version=$version
source_url=$url
install_prefix=$BUILD_DIR/$name
bin_symlinks=$(ls -1 "$BIN_DIR" 2>/dev/null | tr '\n' ' ')
notes=$notes
uninstall=$uninstall
EOF
    success "Manifest saved: $manifest"
}

# ---- Commands ---------------------------------------------------------------
cmd_init() {
    header "Initializing Portable Tools"
    ensure_dirs
    check_mount
    cat > "$ROOT/env.sh" <<EOF
# Source this file in your shell: source $ROOT/env.sh
export PORTABLE_TOOLS_ROOT="$ROOT"
export PATH="\$PORTABLE_TOOLS_ROOT/bin:\$PATH"
export XDG_CACHE_HOME="\$PORTABLE_TOOLS_ROOT/cache"
export XDG_CONFIG_HOME="\$PORTABLE_TOOLS_ROOT/config"
export NPM_CONFIG_CACHE="\$PORTABLE_TOOLS_ROOT/cache/npm"
export NPM_CONFIG_PREFIX="\$PORTABLE_TOOLS_ROOT/build/node"
export GOPATH="\$PORTABLE_TOOLS_ROOT/go"
export CARGO_HOME="\$PORTABLE_TOOLS_ROOT/cargo"
export RUSTUP_HOME="\$PORTABLE_TOOLS_ROOT/rustup"
export NIX_USER_PROFILE_DIR="\$PORTABLE_TOOLS_ROOT/nix-profile"
EOF
    success "Initialized at $ROOT"
    echo -e "\n${BOLD}Add this to your ~/.bashrc or ~/.zshrc:${NC}"
    echo -e "  source $ROOT/env.sh"
}

cmd_check() {
    header "Safety Check"
    ensure_dirs
    check_mount
    info "Tools root : $ROOT"
    info "Free space : $(df -h "$ROOT" | tail -1 | awk '{print $4}')"
    info "Home usage : $(df -h "$HOME" 2>/dev/null | tail -1 | awk '{print $5}') used (should stay low)"
    success "All good — installs will NOT fill your /home partition."
}

cmd_list() {
    header "Installed Tools"
    ensure_dirs
    local count=0
    for mf in "$MANIFESTS_DIR"/*.manifest; do
        [ -f "$mf" ] || continue
        count=$((count+1))
        local name version
        name=$(grep "^name=" "$mf" | cut -d= -f2)
        version=$(grep "^version=" "$mf" | cut -d= -f2)
        printf "  %-20s v%-15s  → %s\n" "$name" "$version" "$(grep '^install_prefix=' "$mf" | cut -d= -f2)"
    done
    [ "$count" -eq 0 ] && echo "  (no tools installed yet — try: $0 install node)"
    echo ""
}

cmd_info() {
    local name="${1:-}"
    [ -z "$name" ] && error "Usage: $0 info <tool-name>"
    local mf="$MANIFESTS_DIR/${name}.manifest"
    [ -f "$mf" ] || error "No manifest found for '$name'"
    header "$name details"
    cat "$mf"
}

cmd_logs() {
    header "Install History"
    ls -lt "$LOGS_DIR" 2>/dev/null | grep -v "^total" | head -15 || echo "(no logs yet)"
    local latest
    latest=$(ls -t "$LOGS_DIR"/install_*.log 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        echo -e "\n${BOLD}Latest log ($(basename "$latest")):${NC}"
        tail -n 25 "$latest"
    fi
}

cmd_uninstall() {
    local name="${1:-}"
    [ -z "$name" ] && error "Usage: $0 uninstall <tool-name>"
    local mf="$MANIFESTS_DIR/${name}.manifest"
    [ -f "$mf" ] || error "Tool '$name' not found (run '$0 list')"
    warn "Uninstalling $name..."
    local uninstall_cmd
    uninstall_cmd=$(grep "^uninstall=" "$mf" | cut -d= -f2-)
    log "UNINSTALL: $name — $uninstall_cmd"
    bash -c "$uninstall_cmd" && rm -f "$mf"
    success "$name removed."
}

# ---- Installers -------------------------------------------------------------
install_node() {
    local NODE_VERSION="${NODE_VERSION:-v20.18.0}"
    local ARCH
    ARCH=$(uname -m)
    local DIR_NAME="node-${NODE_VERSION}-linux-${ARCH}"
    local URL="https://nodejs.org/dist/${NODE_VERSION}/${DIR_NAME}.tar.xz"
    local INSTALL_PATH="$BUILD_DIR/node"

    info "Downloading Node.js $NODE_VERSION ($ARCH)..."
    cd "$TMP_DIR"
    curl -fL --retry 3 "$URL" -o "node.tar.xz" || error "Download failed"
    tar -xf "node.tar.xz" || error "Extraction failed"
    rm -rf "$INSTALL_PATH"
    mv "$DIR_NAME" "$INSTALL_PATH"
    ln -sf "$INSTALL_PATH/bin/node" "$BIN_DIR/node"
    ln -sf "$INSTALL_PATH/bin/npm"  "$BIN_DIR/npm"
    ln -sf "$INSTALL_PATH/bin/npx"  "$BIN_DIR/npx"
    rm -f "node.tar.xz"

    # Configure npm to stay in goinfre
    "$BIN_DIR/npm" config set cache "$CACHE_DIR/npm" --global 2>/dev/null || true
    "$BIN_DIR/npm" config set prefix "$INSTALL_PATH" --global 2>/dev/null || true

    init_manifest "node" "$NODE_VERSION" "$URL" \
        "Node.js + npm + npx. npm cache & prefix redirected to goinfre." \
        "rm -rf $INSTALL_PATH; rm -f $BIN_DIR/node $BIN_DIR/npm $BIN_DIR/npx"
    success "Node.js ready: node -v → $("$BIN_DIR/node" -v)"
}

install_nix_sandbox() {
    info "Setting up sandboxed Nix (no daemon, no sudo)..."
    local NIX_VERSION="${NIX_VERSION:-2.24.0}"
    local INSTALL_DIR="$BUILD_DIR/nix-sandbox"
    local NIX_HOME="$ROOT/nix-home"
    mkdir -p "$INSTALL_DIR" "$NIX_HOME"

    cat > "$BIN_DIR/nix-run" <<'SCRIPT'
#!/usr/bin/env bash
# Wrapper: runs nix with HOME redirected to goinfre so nothing touches /home
export HOME="$(dirname "$(dirname "$(readlink -f "$0")")")/nix-home"
exec "$(dirname "$(dirname "$(readlink -f "$0")")")/build/nix-sandbox/bin/nix" "$@"
SCRIPT
    chmod +x "$BIN_DIR/nix-run"

    cat > "$NIX_HOME/README.txt" <<EOF
Nix sandbox home. All nix state lives here under $ROOT.
Use 'nix-run' to invoke nix commands. Nothing touches your real /home.
EOF

    init_manifest "nix-sandbox" "$NIX_VERSION" "https://nixos.org/download" \
        "Sandboxed nix. Use 'nix-run <cmd>'. Binary must be placed in $INSTALL_DIR manually or via nix-portable." \
        "rm -rf $INSTALL_DIR $NIX_HOME; rm -f $BIN_DIR/nix-run"
    success "Nix sandbox wrapper ready. Place a nix-portable binary at $INSTALL_DIR/bin/nix to use it."
}

install_git() {
    # Portable git via static binary (works without system git)
    local GIT_VERSION="${GIT_VERSION:-2.43.0}"
    local URL="https://github.com/git/git/archive/refs/tags/v${GIT_VERSION}.tar.gz"
    info "Building git $GIT_VERSION from source (needs gcc/make)..."
    cd "$TMP_DIR"
    curl -fL --retry 3 "$URL" -o "git.tar.gz" || error "Download failed"
    tar -xzf "git.tar.gz"
    cd "git-${GIT_VERSION}"
    make configure 2>/dev/null || true
    if [ -f ./configure ]; then
        ./configure --prefix="$BUILD_DIR/git"
    else
        make prefix="$BUILD_DIR/git" all
    fi
    make prefix="$BUILD_DIR/git" install || error "Build failed"
    ln -sf "$BUILD_DIR/git/bin/git" "$BIN_DIR/git"
    cd "$TMP_DIR" && rm -rf "git.tar.gz" "git-${GIT_VERSION}"
    init_manifest "git" "$GIT_VERSION" "$URL" "Built from source." \
        "rm -rf $BUILD_DIR/git; rm -f $BIN_DIR/git"
    success "git ready: $("$BIN_DIR/git" --version)"
}

install_ripgrep() {
    local VERSION="${RIPGREP_VERSION:-14.1.0}"
    local ARCH
    ARCH=$(uname -m)
    local URL="https://github.com/BurntSushi/ripgrep/releases/download/${VERSION}/ripgrep-${VERSION}-x86_64-unknown-linux-musl.tar.gz"
    [ "$ARCH" = "aarch64" ] && URL="https://github.com/BurntSushi/ripgrep/releases/download/${VERSION}/ripgrep-${VERSION}-aarch64-unknown-linux-gnu.tar.gz"
    info "Downloading ripgrep $VERSION..."
    cd "$TMP_DIR"
    curl -fL --retry 3 "$URL" -o "rg.tar.gz" || error "Download failed"
    tar -xzf "rg.tar.gz"
    local dir
    dir=$(ls -d ripgrep-*/ | head -1)
    mkdir -p "$BUILD_DIR/ripgrep/bin"
    cp "${dir}rg" "$BUILD_DIR/ripgrep/bin/rg"
    ln -sf "$BUILD_DIR/ripgrep/bin/rg" "$BIN_DIR/rg"
    rm -rf "rg.tar.gz" "$dir"
    init_manifest "ripgrep" "$VERSION" "$URL" "Fast grep alternative." \
        "rm -rf $BUILD_DIR/ripgrep; rm -f $BIN_DIR/rg"
    success "ripgrep ready: $("$BIN_DIR/rg" --version | head -1)"
}

install_fzf() {
    local VERSION="${FZF_VERSION:-0.46.1}"
    local URL="https://github.com/junegunn/fzf/releases/download/v${VERSION}/fzf-${VERSION}-linux_amd64.tar.gz"
    info "Downloading fzf $VERSION..."
    cd "$TMP_DIR"
    curl -fL --retry 3 "$URL" -o "fzf.tar.gz" || error "Download failed"
    tar -xzf "fzf.tar.gz"
    mkdir -p "$BUILD_DIR/fzf/bin"
    mv fzf "$BUILD_DIR/fzf/bin/fzf"
    chmod +x "$BUILD_DIR/fzf/bin/fzf"
    ln -sf "$BUILD_DIR/fzf/bin/fzf" "$BIN_DIR/fzf"
    rm -f "fzf.tar.gz"
    init_manifest "fzf" "$VERSION" "$URL" "Fuzzy finder." \
        "rm -rf $BUILD_DIR/fzf; rm -f $BIN_DIR/fzf"
    success "fzf ready."
}

install_neovim() {
    local VERSION="${NVIM_VERSION:-v0.10.1}"
    local URL="https://github.com/neovim/neovim/releases/download/${VERSION}/nvim-linux-x86_64.tar.gz"
    info "Downloading Neovim $VERSION..."
    cd "$TMP_DIR"
    curl -fL --retry 3 "$URL" -o "nvim.tar.gz" || error "Download failed"
    tar -xzf "nvim.tar.gz"
    rm -rf "$BUILD_DIR/nvim"
    mv nvim-linux-x86_64 "$BUILD_DIR/nvim"
    ln -sf "$BUILD_DIR/nvim/bin/nvim" "$BIN_DIR/nvim"
    ln -sf "$BUILD_DIR/nvim/bin/nvim" "$BIN_DIR/vim"
    rm -f "nvim.tar.gz"
    init_manifest "neovim" "$VERSION" "$URL" "Neovim editor (also aliased as vim)." \
        "rm -rf $BUILD_DIR/nvim; rm -f $BIN_DIR/nvim $BIN_DIR/vim"
    success "Neovim ready: $("$BIN_DIR/nvim" --version | head -1)"
}

cmd_install() {
    local tool="${1:-}"
    [ -z "$tool" ] && { echo "Available tools: node, nix-sandbox, git, ripgrep, fzf, neovim"; exit 1; }
    ensure_dirs
    check_mount
    header "Installing: $tool"
    case "$tool" in
        node|nodejs|npm)        install_node ;;
        nix|nix-sandbox)        install_nix_sandbox ;;
        git)                    install_git ;;
        ripgrep|rg)             install_ripgrep ;;
        fzf)                    install_fzf ;;
        neovim|nvim)            install_neovim ;;
        *) error "Unknown tool: $tool (available: node, nix-sandbox, git, ripgrep, fzf, neovim)" ;;
    esac
}

cmd_update() {
    local name="${1:-}"
    [ -z "$name" ] && error "Usage: $0 update <tool-name>"
    warn "Re-installing $name (latest version)..."
    cmd_uninstall "$name" 2>/dev/null || true
    cmd_install "$name"
}

# ---- Usage ------------------------------------------------------------------
usage() {
    cat <<EOF
${BOLD}Portable Tools Manager${NC} — install anything under /goinfre, no sudo, no /home bloat.

${BOLD}Usage:${NC} $0 <command> [args]

${BOLD}Setup:${NC}
  init                  Create directories + env.sh (run once)
  check                 Verify mount point & free space

${BOLD}Install:${NC}
  install <tool>        Install a tool (node, nix-sandbox, git, ripgrep, fzf, neovim)
  update <tool>         Re-install a tool (latest version)
  uninstall <tool>      Remove a tool completely

${BOLD}Manage:${NC}
  list                  Show all installed tools
  info <tool>           Show manifest details for a tool
  logs                  View install history

${BOLD}Env:${NC}
  After 'init', add to your ~/.bashrc:  source $ROOT/env.sh

${BOLD}Examples:${NC}
  $0 init
  $0 install node
  $0 list
  $0 info node
  $0 uninstall node
EOF
}

# ---- Main -------------------------------------------------------------------
ensure_dirs
touch "$LOG_FILE" 2>/dev/null || true

case "${1:-help}" in
    init)           cmd_init ;;
    check)          cmd_check ;;
    list|ls)        cmd_list ;;
    info|show)      cmd_info "${2:-}" ;;
    install)        cmd_install "${2:-}" ;;
    update|upgrade) cmd_update "${2:-}" ;;
    uninstall|rm)   cmd_uninstall "${2:-}" ;;
    logs|history)   cmd_logs ;;
    help|--help|-h) usage ;;
    *)              error "Unknown command: $1 (run '$0 help')" ;;
esac
