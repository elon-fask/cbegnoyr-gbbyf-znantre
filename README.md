# Portable Tools Manager

Install any tool under `/goinfre` on school workstations — **no sudo, no `/home` quota bloat**. Built for 42-style schools where `/home` is tiny (4.7 GB) but `/goinfre` has hundreds of GB free.

## Why

On school workstations:
- `/home/<you>` is only ~4.7 GB and fills up fast
- You're not in the `sudo` group
- `/goinfre/<you>` has hundreds of GB but gets wiped periodically
- Every tool you install (npm, node, git, neovim, etc.) wants to write to `~/.cache`, `~/.config`, `~/.npm`...

This manager redirects **everything** to `/goinfre/<you>/portable_tools` and keeps a full manifest + log of every tool so you can update, remove, or rebuild them without guessing.

## Quick Start

```bash
# 1. Clone or download this repo
git clone <your-repo-url> ~/ptm && cd ~/ptm

# 2. Initialize (creates directories + env.sh)
./manager.sh init

# 3. Add to your shell config (printed by init)
echo 'source /goinfre/$USER/portable_tools/env.sh' >> ~/.bashrc

# 4. Install tools
./manager.sh install node
./manager.sh install neovim
./manager.sh install ripgrep
./manager.sh install fzf

# 5. Verify
./manager.sh list
./manager.sh check
node -v   # works! and nothing touched /home
```

## One-liner for classmates

```bash
curl -fsSL <raw-url>/bootstrap.sh | bash
```

## Commands

| Command | Description |
|---------|-------------|
| `init` | Create directories + `env.sh` (run once) |
| `check` | Verify mount point & free space (safety) |
| `install <tool>` | Install a tool |
| `update <tool>` | Re-install with latest version |
| `uninstall <tool>` | Remove a tool completely |
| `list` | Show all installed tools |
| `info <tool>` | Show manifest details |
| `logs` | View install history |

### Available tools
`node` (npm/npx), `nix-sandbox`, `git`, `ripgrep` (rg), `fzf`, `neovim` (nvim/vim)

Add your own by copying an `install_*` function in `manager.sh`.

## How it works

```
/goinfre/<you>/portable_tools/
├── bin/          → symlinks to every executable (added to your PATH)
├── build/        → actual installed files per tool
├── src/          → source code when building from scratch
├── manifests/    → one .manifest file per tool (version, url, uninstall cmd)
├── logs/         → timestamped install/uninstall history
├── tmp/          → temporary downloads (safe to delete)
├── cache/        → npm/cargo/go caches redirected here
├── env.sh        → source this in your shell
├── manager.sh    → bash CLI (full functionality)
└── manager.lua   → Lua version (learning companion, read-only commands)
```

### Manifest example
Every tool gets a `manifests/<name>.manifest`:
```
name=node
version=v20.18.0
source_url=https://nodejs.org/dist/...
install_prefix=/goinfre/.../build/node
notes=Node.js + npm + npx...
uninstall=rm -rf .../build/node; rm -f .../bin/node ...
```

This means you can **always** cleanly remove or rebuild any tool, even months later.

## Adding a new tool (contribute!)

1. Open `manager.sh`, find an `install_*` function (e.g. `install_ripgrep`)
2. Copy it, rename it, change the URL/version/paths
3. Add a case in `cmd_install`
4. Test: `./manager.sh install <your-tool>`
5. Send a PR!

## Lua version

`manager.lua` mirrors the read-only commands (`list`, `info`, `check`, `logs`) in Lua. Use it to learn Lua — the manifest file format is identical, so both managers share the same state.

## Safety

- `check_mount()` runs before every install and **aborts** if the target resolves to `/home`
- `env.sh` redirects `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `NPM_CONFIG_*`, `GOPATH`, `CARGO_HOME`, `RUSTUP_HOME` to goinfre
- Always run `./manager.sh check` first on a new workstation

## License

MIT — use it, fork it, share it with your classmates.
