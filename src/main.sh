# main.sh — Dispatcher: sources libs/commands, parses args, routes to cmd_*

# Source libraries
source "$REPO_DIR/src/lib/colors.sh"
source "$REPO_DIR/src/lib/toml.sh"
source "$REPO_DIR/src/lib/backup.sh"
source "$REPO_DIR/src/lib/symlink.sh"
source "$REPO_DIR/src/lib/util.sh"

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +%Y-%m-%d.%H%M%S)
DRY_RUN=false
TOML="$REPO_DIR/nx-agents.toml"
STORE_DIR="$REPO_DIR/store"
REMOVED_DIR="$REPO_DIR/.removed.$TIMESTAMP"

# Parse default + user config, merge
TOML_JSON_DEFAULT="$(parse_toml "$TOML")"
USER_CONFIG_JSON="$(load_user_config)"
TOML_JSON="$(merge_configs "$TOML_JSON_DEFAULT" "$USER_CONFIG_JSON")"

# Config values from merged TOML
tq() { echo "$TOML_JSON" | jq -r "$@" 2>/dev/null || true; }

CONFIG_NAME=$(tq '.config.name // "nx-agents-config"')
CONFIG_REPO=$(tq '.config.repo // "~/.nx-agents-config"')
CONFIG_HOME=$(tq '.config.home // "~/.nx-agents-config"')

# Source commands
source "$REPO_DIR/src/commands/tree.sh"
source "$REPO_DIR/src/commands/setup.sh"
source "$REPO_DIR/src/commands/update.sh"
source "$REPO_DIR/src/commands/sync.sh"
source "$REPO_DIR/src/commands/project.sh"
source "$REPO_DIR/src/commands/tool.sh"
source "$REPO_DIR/src/commands/update-tool.sh"
source "$REPO_DIR/src/commands/uninstall.sh"

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
  update-tool           Update nx-agents-config tool (git pull)
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
