# main.sh — Dispatcher: sources libs/commands, parses args, routes to cmd_*

# Source libraries
source "$NX_AGENTS_HOME/src/lib/colors.sh"
source "$NX_AGENTS_HOME/src/lib/toml.sh"
source "$NX_AGENTS_HOME/src/lib/backup.sh"
source "$NX_AGENTS_HOME/src/lib/symlink.sh"
source "$NX_AGENTS_HOME/src/lib/util.sh"

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +%Y-%m-%d.%H%M%S)
DRY_RUN=false
STORE_DIR="$NX_AGENTS_HOME/store"
REMOVED_DIR="$NX_AGENTS_HOME/.removed.$TIMESTAMP"

# Parse default + user config, merge
if [[ -f "$NX_AGENTS_HOME/nx-agents.toml" ]]; then
  TOML_JSON_DEFAULT="$(parse_toml "$NX_AGENTS_HOME/nx-agents.toml")"
else
  TOML_JSON_DEFAULT="$(parse_toml_stdin <<< "$DEFAULT_TOML")"
fi
USER_CONFIG_JSON="$(load_user_config)"
TOML_JSON="$(merge_configs "$TOML_JSON_DEFAULT" "$USER_CONFIG_JSON")"

# Config values from merged TOML
tq() { echo "$TOML_JSON" | jq -r "$@" 2>/dev/null || true; }

CONFIG_NAME=$(tq '.config.name // "nx-agents-config"')

# Source commands
source "$NX_AGENTS_HOME/src/commands/tree.sh"
source "$NX_AGENTS_HOME/src/commands/setup.sh"
source "$NX_AGENTS_HOME/src/commands/update.sh"
source "$NX_AGENTS_HOME/src/commands/sync.sh"
source "$NX_AGENTS_HOME/src/commands/project.sh"
source "$NX_AGENTS_HOME/src/commands/tool.sh"
source "$NX_AGENTS_HOME/src/commands/update-tool.sh"
source "$NX_AGENTS_HOME/src/commands/claude.sh"
source "$NX_AGENTS_HOME/src/commands/uninstall.sh"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
cmd_help() {
  cat <<EOF
${BOLD}nx-agents-config${NC} — Centralized coding agent configuration

${BOLD}Usage:${NC}  nx-agents-config <command> [options]

${BOLD}Commands:${NC}
  tree                  Show configured directory tree
  setup                 Initial setup (create store, symlinks, backups)
  update                Reconcile filesystem to match config
  sync                  Git sync your store/ data
  project add <name>    Add a new project
  project list          List projects
  tool add <name>       Scaffold a new tool in store/config.toml
  claude restore        Restore Claude data from backup into store/
  update-tool           Update nx-agents-config tool (download template)
  uninstall             Backup store + remove everything

${BOLD}Options:${NC}
  --dry-run             Preview changes without making them
  --no-color            Disable colored output
  -h, --help            Show this help

EOF
}

# ---------------------------------------------------------------------------
# Parse global options
# ---------------------------------------------------------------------------
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --no-color)
      GREEN=''; CYAN=''; YELLOW=''; RED=''; BOLD=''; DIM=''; NC=''
      ICON_OK="[ok]"; ICON_LINK="->"; ICON_SKIP="[-]"; ICON_ERR="[err]"; ICON_WARN="[!]"
      ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]}"

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-help}" in
  tree) shift; cmd_tree "$@" ;;
  setup) shift; cmd_setup "$@" ;;
  update) shift; cmd_update "$@" ;;
  sync) shift; cmd_sync "$@" ;;
  update-tool) shift; cmd_update_tool "$@" ;;
  uninstall) shift; cmd_uninstall "$@" ;;
  claude)
    shift
    cmd_claude "$@"
    ;;
  project)
    shift
    cmd_project "$@"
    ;;
  tool)
    shift
    cmd_tool "$@"
    ;;
  help|--help|-h|"")
    cmd_help
    ;;
  *)
    err "Unknown command: $1"
    echo "Usage: nx-agents-config help"
    exit 1
    ;;
esac
