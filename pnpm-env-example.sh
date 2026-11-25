# pnpm environment — sourced from ~/.zshrc (or manually)
export PNPM_HOME="/goinfre/atboulaa/pnpm"
export XDG_DATA_HOME="/goinfre/atboulaa/.local/share"
export XDG_CACHE_HOME="/goinfre/atboulaa/.cache"
export XDG_CONFIG_HOME="/goinfre/atboulaa/.config"
export XDG_STATE_HOME="/goinfre/atboulaa/.local/state"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH" ;;
esac
