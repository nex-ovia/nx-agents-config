# restoreFromBkp.sh — Restore tool data from ~/.<tool>.bak.*/ backups

cmd_restoreFromBkp() {
  local tool="${1:-claude}"
  shift 2>/dev/null || true

  if ! tool_exists "$tool" >/dev/null; then
    err "Unknown tool: $tool"
    echo "Usage: nx-agents-config restoreFromBkp [tool]"
    exit 1
  fi

  local data_dir
  data_dir=$(tool_data "$tool")
  local expanded_data="${data_dir/#\~/$HOME}"

  local cs="$STORE_DIR/$tool"

  # Special handling: if data dir is same as store dir (symlinked), restore into store
  if [[ -z "$data_dir" || "$expanded_data" == "$cs" ]]; then
    cmd_restore_into_store "$tool"
    return
  fi

  # Generic restore: copy backup back to data dir
  cmd_restore_to_data "$tool"
}

# Restore Claude data from backup into store/ (original behavior)
cmd_restore_into_store() {
  local tool="$1"
  local backup_dir=""
  for d in "$HOME"/.${tool}.bak.*/; do
    [[ -d "$d" ]] && backup_dir="$d"
  done

  if [[ -z "$backup_dir" ]]; then
    err "No backup found at ~/.${tool}.bak.*/"
    exit 1
  fi

  heading "Restoring $tool data from backup"
  dim "Backup: $backup_dir"
  dim "Store:  $STORE_DIR/$tool/"

  local cs="$STORE_DIR/$tool"

  restore_dir() {
    local rel="$1" label="$2"
    local src="$backup_dir/$rel"
    local dst="$cs/$rel"
    [[ -d "$src" ]] || return 0
    heading "$label"
    run mkdir -p "$dst"
    for item in "$src"/*; do
      [[ -e "$item" ]] || continue
      local base
      base=$(basename "$item")
      if [[ -e "$dst/$base" ]]; then
        skip "Already exists: $rel/$base"
      else
        run cp -a "$item" "$dst/$base"
        info "Restored: $rel/$base"
      fi
    done
  }

  restore_file_if() {
    local rel="$1" label="$2"
    local src="$backup_dir/$rel"
    local dst="$cs/$rel"
    [[ -f "$src" ]] || return 0
    heading "$label"
    if [[ -f "$dst" ]]; then
      skip "Already exists: $rel"
    else
      run cp "$src" "$dst"
      info "Restored: $rel"
    fi
  }

  restore_dir "projects" "Projects"
  restore_dir "sessions" "Sessions"
  restore_dir "file-history" "File history"
  restore_dir "plans" "Plans"
  restore_dir "backups" "Config backups"
  restore_dir "ide" "IDE config"
  restore_dir "shell-snapshots" "Shell snapshots"
  restore_file_if "settings.json" "Settings"
  restore_file_if "CLAUDE.md" "CLAUDE.md"

  if [[ "$tool" == "claude" ]]; then
    heading "Claude config (.claude.json)"
    local json_src="$HOME/.claude.json"
    local json_dst="$cs/.claude.json"
    if [[ -L "$json_src" ]]; then
      local current
      current=$(readlink "$json_src")
      if [[ "$current" == "$json_dst" ]]; then
        skip ".claude.json symlink already correct"
      else
        warn ".claude.json symlink points elsewhere: $current"
      fi
    elif [[ -f "$json_src" ]]; then
      if ${DRY_RUN:-false}; then
        skip "(would backup .claude.json to store and symlink)"
      else
        cp "$json_src" "$json_dst"
        info "Backed up .claude.json to store"
        rm "$json_src"
        ln -s "$json_dst" "$json_src"
        link "Symlinked .claude.json -> store"
      fi
    else
      if ! ${DRY_RUN:-false}; then
        echo "{}" > "$json_dst"
        ln -s "$json_dst" "$json_src"
        info "Created empty .claude.json in store with symlink"
      fi
    fi
  fi

  if [[ -d "$STORE_DIR/.git" ]]; then
    echo ""
    echo -n "  Commit restored data to store? [y/N] "
    read -r do_commit
    if [[ "$do_commit" =~ ^[Yy] ]]; then
      echo -n "  Commit message: "
      read -r msg
      msg="${msg:-Restore $tool data from backup}"
      run git -C "$STORE_DIR" add -A
      run git -C "$STORE_DIR" commit -m "$msg"
      info "Committed restored data"
    fi
  fi

  echo ""
  info "Restore complete!"
  dim "Restart $tool or reload VSCode to pick up restored sessions."
}

# Generic restore: copy backup back to original data dir
cmd_restore_to_data() {
  local tool="$1"
  local data_dir
  data_dir=$(tool_data "$tool")
  local expanded_data="${data_dir/#\~/$HOME}"

  local backup_dir=""
  for d in "$HOME"/.${tool}.bak.*/; do
    [[ -d "$d" ]] && backup_dir="$d"
  done

  if [[ -z "$backup_dir" ]]; then
    err "No backup found at ~/.${tool}.bak.*/"
    exit 1
  fi

  heading "Restoring $tool data from backup"
  dim "Backup: $backup_dir"
  dim "Target: $expanded_data"

  if [[ ! -d "$expanded_data" ]]; then
    warn "Target directory does not exist: $expanded_data"
    echo -n "  Create it? [Y/n] "
    read -r create
    if [[ -z "$create" || "$create" =~ ^[Yy] ]]; then
      run mkdir -p "$expanded_data"
    else
      skip "Cancelled"
      exit 0
    fi
  fi

  echo ""
  echo -n "  This will overwrite files in $expanded_data. Continue? [y/N] "
  read -r confirm
  [[ "$confirm" =~ ^[Yy] ]] || { skip "Cancelled"; exit 0; }

  if ${DRY_RUN:-false}; then
    skip "(would restore) $backup_dir → $expanded_data"
  else
    run cp -a "$backup_dir"/. "$expanded_data"/
    info "Restored $tool data from backup"
  fi

  echo ""
  info "Restore complete!"
  dim "Restart $tool to pick up restored data."
}
