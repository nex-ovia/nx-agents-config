# claude.sh — Claude-specific operations

cmd_claude() {
  local subcmd="${1:-help}"
  shift 2>/dev/null || true

  case "$subcmd" in
    restore) cmd_claude_restore "$@" ;;
    help|--help|-h|"")
      cat <<EOF
Usage: nx-agents-config claude <command>

Commands:
  restore          Restore Claude data from backup into store/
EOF
      ;;
    *)
      err "Unknown claude command: $subcmd"
      echo "Usage: nx-agents-config claude help"
      exit 1
      ;;
  esac
}

cmd_claude_restore() {
  local backup_dir=""
  for d in "$HOME"/.claude.bak.*/; do
    [[ -d "$d" ]] && backup_dir="$d"
  done

  if [[ -z "$backup_dir" ]]; then
    err "No backup found at ~/.claude.bak.*/"
    exit 1
  fi

  heading "Restoring Claude data from backup"
  dim "Backup: $backup_dir"
  dim "Store:  $STORE_DIR/claude/"

  local cs="$STORE_DIR/claude"

  # Restore subdirectory from backup into store
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

  # Handle ~/.claude.json
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

  # Offer to commit
  if [[ -d "$STORE_DIR/.git" ]]; then
    echo ""
    echo -n "  Commit restored data to store? [y/N] "
    read -r do_commit
    if [[ "$do_commit" =~ ^[Yy] ]]; then
      echo -n "  Commit message: "
      read -r msg
      msg="${msg:-Restore Claude data from backup}"
      run git -C "$STORE_DIR" add -A
      run git -C "$STORE_DIR" commit -m "$msg"
      info "Committed restored data"
    fi
  fi

  echo ""
  info "Restore complete!"
  dim "Restart Claude or reload VSCode to pick up restored sessions."
}
