#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TOML="$REPO_DIR/nx-agents.toml"
TIMESTAMP=$(date +%Y-%m-%d.%H%M%S)
DRY_RUN=false
REMOVED_DIR="$REPO_DIR/.removed.$TIMESTAMP"

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
  RED='\033[0;31m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
  ICON_OK="${GREEN}✓${NC}"; ICON_LINK="${CYAN}→${NC}"
  ICON_SKIP="${YELLOW}−${NC}"; ICON_ERR="${RED}✗${NC}"
else
  GREEN=''; CYAN=''; YELLOW=''; RED=''; BOLD=''; DIM=''; NC=''
  ICON_OK="[ok]"; ICON_LINK="->"; ICON_SKIP="[-]"; ICON_ERR="[err]"
fi

TOML_JSON=$(python3 -c "
import tomllib, json
with open('${TOML}', 'rb') as f:
    print(json.dumps(tomllib.load(f)))
" 2>/dev/null || echo "{}")

tq()   { echo "$TOML_JSON" | jq -r "$@" 2>/dev/null || true; }
info() { echo -e "  ${ICON_OK} $1"; }
link() { echo -e "  ${ICON_LINK} $1"; }
skip() { echo -e "  ${ICON_SKIP} $1"; }
err()  { echo -e "  ${ICON_ERR} $1"; }
heading() { echo -e "\n${BOLD}$1${NC}"; }
dim()    { echo -e "${DIM}$1${NC}"; }

run() {
  if $DRY_RUN; then
    skip "(would run) $*"
  else
    "$@"
  fi
}

backup() {
  local src="$1" label="$2"
  if [[ -e "$src" ]]; then
    local bak="${src}.bak.${TIMESTAMP}"
    if $DRY_RUN; then
      skip "(would backup) $label → $bak"
    else
      mv "$src" "$bak"
      link "Backed up $label → $bak"
    fi
  fi
}

ensure_dir() {
  local dir="$1" desc="$2"
  if [[ ! -d "$dir" ]]; then
    run mkdir -p "$dir"
    run touch "$dir/.gitkeep"
    info "Created $desc: $dir"
  fi
}

ensure_symlink() {
  local target="$1" link_path="$2" desc="$3"
  if [[ -L "$link_path" ]]; then
    local current=$(readlink "$link_path")
    if [[ "$current" == "$target" ]]; then
      skip "Symlink already correct: $desc"
      return
    fi
    run rm "$link_path"
    link "Replaced symlink: $desc"
  elif [[ -e "$link_path" ]]; then
    run rm -rf "$link_path"
    link "Replaced existing path: $desc"
  fi
  if ! $DRY_RUN; then
    ln -s "$target" "$link_path"
  fi
  link "Symlink: $desc"
}

ensure_external_symlink() {
  local target="$1" link_path="$2" desc="$3"
  local expanded_link="${link_path/#\~/$HOME}"
  local expanded_target="${target/#\~/$HOME}"

  if [[ -L "$expanded_link" ]]; then
    local current=$(readlink "$expanded_link")
    if [[ "$current" == "$expanded_target" ]]; then
      skip "External symlink already correct: $desc"
      return
    fi
    run rm "$expanded_link"
    link "Replaced external symlink: $desc"
  elif [[ -e "$expanded_link" ]]; then
    backup "$expanded_link" "$desc config"
    if $DRY_RUN; then
      skip "(would symlink) $expanded_link → $expanded_target"
    else
      ln -s "$expanded_target" "$expanded_link"
      link "External symlink: $desc ($expanded_link)"
    fi
  else
    if $DRY_RUN; then
      skip "(would symlink) $expanded_link → $expanded_target"
    else
      mkdir -p "$(dirname "$expanded_link")"
      ln -s "$expanded_target" "$expanded_link"
      link "External symlink: $desc ($expanded_link)"
    fi
  fi
}

ensure_file() {
  local filepath="$1" desc="$2"
  if [[ ! -f "$filepath" ]]; then
    skip "Missing file: $desc ($filepath — create manually)"
  else
    skip "File exists: $desc"
  fi
}

move_to_removed() {
  local path="$1" reason="$2"
  local dest="$REMOVED_DIR/$(basename "$path")"
  if $DRY_RUN; then
    skip "(would move to removed) $path — $reason"
  else
    mkdir -p "$REMOVED_DIR"
    mv "$path" "$dest"
    link "Moved to .removed/: $path — $reason"
  fi
}

# ---------------------------------------------------------------------------
# TOML access helpers
# ---------------------------------------------------------------------------
tool_names()        { tq '.tool[].name // empty'; }
tool_desc()         { tq ".tool[] | select(.name == \"$1\") | .desc // \"\""; }
tool_external()     { tq ".tool[] | select(.name == \"$1\") | .external // \"\""; }
tool_int_count()    { tq ".tool[] | select(.name == \"$1\") | (.internal | length) // 0"; }
tool_file_count()   { tq ".tool[] | select(.name == \"$1\") | (.file | length) // 0"; }
tool_int_from()     { tq ".tool[] | select(.name == \"$1\") | .internal[$2].from // \"\""; }
tool_int_to()       { tq ".tool[] | select(.name == \"$1\") | .internal[$2].to // \"\""; }
tool_int_desc()     { tq ".tool[] | select(.name == \"$1\") | .internal[$2].desc // \"\""; }
tool_file_path()    { tq ".tool[] | select(.name == \"$1\") | .file[$2].path // \"\""; }
tool_file_desc()    { tq ".tool[] | select(.name == \"$1\") | .file[$2].desc // \"\""; }
tool_internals_display() {
  tq ".tool[] | select(.name == \"$1\") | .internal[] | \"\(.from) → \(.to)  [\(.desc // \"\")]\"" 2>/dev/null
}
tool_files_display() {
  tq ".tool[] | select(.name == \"$1\") | .file[] | \"\(.path)  [\(.desc // \"\")]\"" 2>/dev/null
}
tool_exists()       { tq ".tool[] | select(.name == \"$1\") | .name // \"\""; }
shared_keys()       { tq '.shared | keys | .[] // empty'; }
shared_path()       { tq ".shared.\"$1\".path // \"\""; }
shared_desc()       { tq ".shared.\"$1\".desc // \"\""; }

CONFIG_NAME=$(tq '.config.name')
CONFIG_REPO=$(tq '.config.repo')
CONFIG_HOME=$(tq '.config.home')

# ---------------------------------------------------------------------------
# cmd: tree
# ---------------------------------------------------------------------------
cmd_tree() {
  echo ""
  heading "${CONFIG_NAME}/  (repo: ${CONFIG_REPO})"

  # shared sections
  echo "├── shared/"
  local keys=()
  while IFS= read -r k; do keys+=("$k"); done < <(shared_keys)
  local last_idx=$((${#keys[@]} - 1))
  for i in "${!keys[@]}"; do
    local k="${keys[$i]}"
    local prefix="│" branch="├──"
    [[ $i -eq $last_idx ]] && { prefix=" "; branch="└──"; }
    echo "$prefix   $branch ${k}/  $(dim "$(shared_desc "$k")")"
  done

  # tools
  local tools=()
  while IFS= read -r t; do tools+=("$t"); done < <(tool_names)
  for t in "${tools[@]}"; do
    local desc=$(tool_desc "$t")
    local ext=$(tool_external "$t")
    echo "├── ${t}/           $(dim "${desc}  (→ ${ext})")"

    # internal symlinks
    local ints=()
    while IFS= read -r line; do ints+=("$line"); done < <(tool_internals_display "$t" 2>/dev/null || true)
    local fls=()
    while IFS= read -r line; do fls+=("$line"); done < <(tool_files_display "$t" 2>/dev/null || true)

    local sub_items=("${ints[@]}" "${fls[@]}")
    local s_last=$((${#sub_items[@]} - 1))
    for si in "${!sub_items[@]}"; do
      local sbranch="├──" sprefix="│"
      [[ $si -eq $s_last ]] && { sbranch="└──"; sprefix=" "; }
      echo "$sprefix   $sbranch ${sub_items[$si]}"
    done
  done

  # repo files
  echo "├── nx-agents.toml      $(dim '[manifest]')"
  echo "├── setup.sh            $(dim '[onboarding script]')"
  echo "├── LICENSE             $(dim '[MIT]')"
  echo "└── README.md           $(dim '[documentation]')"

  # external symlinks summary
  echo ""
  heading "External symlinks:"
  for t in "${tools[@]}"; do
    local ext=$(tool_external "$t")
    echo "  ${ext}  →  ${CONFIG_REPO}/${t}/"
  done
  # home symlink
  echo "  ${CONFIG_HOME}  →  ${CONFIG_REPO}/"
}

# ---------------------------------------------------------------------------
# cmd: setup
# ---------------------------------------------------------------------------
cmd_setup() {
  heading "Setting up ${CONFIG_NAME}..."
  dim "Timestamp: $TIMESTAMP"

  # 1. Home symlink
  local home_expanded="${CONFIG_HOME/#\~/$HOME}"
  local repo_expanded="${CONFIG_REPO/#\~/$HOME}"
  ensure_external_symlink "$repo_expanded" "$home_expanded" "Home → repo"

  # 2. Shared directories
  heading "Shared resources"
  while IFS= read -r k; do
    local rel_path="$(shared_path "$k")"
    ensure_dir "$REPO_DIR/$rel_path" "shared/$k ($(shared_desc "$k"))"
  done < <(shared_keys)

  # 3. Tools
  while IFS= read -r t; do
    local desc=$(tool_desc "$t")
    local ext=$(tool_external "$t")
    local tool_dir="$REPO_DIR/$t"

    heading "Tool: $t ($desc)"
    ensure_dir "$tool_dir" "$t directory"

    # Internal symlinks
    local int_count=$(tool_int_count "$t")
    if [[ "$int_count" != "0" ]]; then
      for i in $(seq 0 $((int_count - 1))); do
        local from=$(tool_int_from "$t" "$i")
        local to=$(tool_int_to "$t" "$i")
        local idesc=$(tool_int_desc "$t" "$i")
        local link_path="$tool_dir/$from"
        local target_path="$REPO_DIR/$to"
        ensure_symlink "$target_path" "$link_path" "$idesc"
      done
    fi

    # Config files
    local f_count=$(tool_file_count "$t")
    if [[ "$f_count" != "0" ]]; then
      for i in $(seq 0 $((f_count - 1))); do
        local fpath=$(tool_file_path "$t" "$i")
        local fdesc=$(tool_file_desc "$t" "$i")
        ensure_file "$tool_dir/$fpath" "$fdesc"
      done
    fi

    # External symlink
    ensure_external_symlink "$tool_dir" "$ext" "$desc"
  done < <(tool_names)

  echo ""
  info "Setup complete! Run '${BOLD}nx-agents-config tree${NC}' to verify."
}

# ---------------------------------------------------------------------------
# cmd: update
# ---------------------------------------------------------------------------
cmd_update() {
  heading "Updating ${CONFIG_NAME} from TOML..."

  # 1. Backup repo
  backup "$REPO_DIR/.bak" "previous repo state (if exists)"

  # 2. Shared directories
  heading "Ensuring shared resources"
  while IFS= read -r k; do
    local rel_path="$(shared_path "$k")"
    ensure_dir "$REPO_DIR/$rel_path" "shared/$k ($(shared_desc "$k"))"
  done < <(shared_keys)

  # 3. Tools
  while IFS= read -r t; do
    local desc=$(tool_desc "$t")
    local ext=$(tool_external "$t")
    local tool_dir="$REPO_DIR/$t"

    heading "Tool: $t ($desc)"
    ensure_dir "$tool_dir" "$t directory"

    # Internal symlinks
    local int_count=$(tool_int_count "$t")
    if [[ "$int_count" != "0" ]]; then
      for i in $(seq 0 $((int_count - 1))); do
        local from=$(tool_int_from "$t" "$i")
        local to=$(tool_int_to "$t" "$i")
        local idesc=$(tool_int_desc "$t" "$i")
        local link_path="$tool_dir/$from"
        local target_path="$REPO_DIR/$to"
        ensure_symlink "$target_path" "$link_path" "$idesc"
      done
    fi

    # Config files
    local f_count=$(tool_file_count "$t")
    if [[ "$f_count" != "0" ]]; then
      for i in $(seq 0 $((f_count - 1))); do
        local fpath=$(tool_file_path "$t" "$i")
        local fdesc=$(tool_file_desc "$t" "$i")
        ensure_file "$tool_dir/$fpath" "$fdesc"
      done
    fi

    # External symlink
    ensure_external_symlink "$tool_dir" "$ext" "$desc"
  done < <(tool_names)

  # 4. Orphan detection — repo subdirs not in TOML
  heading "Orphan detection"
  local known=("shared" ".git" ".removed" ".bak")
  while IFS= read -r t; do known+=("$t"); done < <(tool_names)
  known+=("nx-agents.toml" "setup.sh" "LICENSE" "README.md" ".gitignore")

  for entry in "$REPO_DIR"/*; do
    local base=$(basename "$entry")
    [[ -d "$entry" ]] || continue
    local is_known=false
    for k in "${known[@]}"; do [[ "$base" == "$k" ]] && { is_known=true; break; } done
    $is_known && continue
    move_to_removed "$entry" "Not in TOML"
  done

  echo ""
  info "Update complete!"
}

# ---------------------------------------------------------------------------
# cmd: sync
# ---------------------------------------------------------------------------
cmd_sync() {
  heading "Syncing ${CONFIG_NAME}..."
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    err "Not a git repository: $REPO_DIR"
    exit 1
  fi
  (
    cd "$REPO_DIR"
    git fetch --quiet 2>/dev/null || true
    local behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
    if [[ "$behind" != "0" ]]; then
      info "Pulling $behind new commits..."
      git pull --ff-only
    else
      skip "Already up to date"
    fi
  )
}

# ---------------------------------------------------------------------------
# cmd: status
# ---------------------------------------------------------------------------
cmd_status() {
  cmd_tree
  echo ""
  heading "Git status"
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    err "Not a git repository"
    return
  fi
  (
    cd "$REPO_DIR"
    git status --short 2>/dev/null | head -20
    local untracked=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$untracked" == "0" ]]; then
      skip "Clean working tree"
    else
      info "$untracked modified/untracked files"
    fi
  )
}

# ---------------------------------------------------------------------------
# cmd: tool add
# ---------------------------------------------------------------------------
cmd_tool_add() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    err "Usage: nx-agents-config tool add <name>"
    exit 1
  fi
  if ! echo "$name" | grep -qE '^[a-z][a-z0-9_-]+$'; then
    err "Tool name must be lowercase alphanumeric with hyphens/underscores"
    exit 1
  fi
  if [[ -n "$(tool_exists "$name")" ]]; then
    err "Tool '$name' already exists in TOML"
    exit 1
  fi

  heading "Adding tool: $name"

  # Prompt for description
  echo "  Enter description for '$name':"
  read -r desc
  desc="${desc:-$name coding agent}"

  # Prompt for external path
  echo "  Enter external config path for '$name' (e.g., ~/.config/$name):"
  read -r ext_path
  if [[ -z "$ext_path" ]]; then
    ext_path="~/.config/$name"
  fi

  # Append to TOML
  local new_entry="
[[tool]]
name = \"$name\"
desc = \"$desc\"
external = \"$ext_path\"

  [[tool.internal]]
  from = \"skills\"
  to = \"../shared/skills\"
  desc = \"Shared skills\"
"
  local tmp_file=$(mktemp)
  cat "$TOML" > "$tmp_file"
  echo "$new_entry" >> "$tmp_file"
  cp "$tmp_file" "$TOML"
  rm "$tmp_file"
  info "Added '$name' to nx-agents.toml"

  # Create tool directory
  ensure_dir "$REPO_DIR/$name" "$name directory"

  # Internal symlink for skills
  ensure_symlink "$REPO_DIR/shared/skills" "$REPO_DIR/$name/skills" "Shared skills"

  echo ""
  info "Tool '$name' added! Run '${BOLD}nx-agents-config update${NC}' to create external symlinks."
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "${1:-help}" in
  tree|setup|update|sync|status)
    cmd="$1"; shift
    for arg in "$@"; do
      case "$arg" in
        --dry-run) DRY_RUN=true; shift ;;
        --no-color)
          GREEN=''; CYAN=''; YELLOW=''; RED=''; BOLD=''; DIM=''; NC=''
          ICON_OK="[ok]"; ICON_LINK="->"; ICON_SKIP="[-]"; ICON_ERR="[err]"
          ;;
      esac
    done
    "cmd_$cmd" "$@"
    ;;
  tool)
    shift
    case "${1:-help}" in
      add) shift; cmd_tool_add "$@" ;;
      *)
        echo "Usage: nx-agents-config tool add <name>"
        exit 1
        ;;
    esac
    ;;
  help|--help|-h|"")
    echo "${BOLD}nx-agents-config${NC} — Centralized coding agent configuration"
    echo ""
    echo "Usage: nx-agents-config <command> [options]"
    echo ""
    echo "Commands:"
    echo "  tree                  Show configured directory tree"
    echo "  setup                 Initial setup (backup + create symlinks)"
    echo "  update                Reconcile filesystem to match TOML"
    echo "  sync                  git pull --ff-only"
    echo "  status                Show tree + git status"
    echo "  tool add <name>       Scaffold a new tool in TOML"
    echo ""
    echo "Options:"
    echo "  --dry-run             Preview changes without making them"
    echo "  --no-color            Disable colored output"
    ;;
  *)
    err "Unknown command: $1"
    echo "Usage: nx-agents-config help"
    exit 1
    ;;
esac
