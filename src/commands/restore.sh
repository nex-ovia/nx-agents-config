# restore.sh — Clone remote store and wire all symlinks (new device restore)

cmd_restore() {
  local remote="${1:-}"
  if [[ -z "$remote" ]]; then
    err "Usage: nx-agents-config restore <remote-url>"
    exit 1
  fi

  heading "Restoring store from remote"
  dim "Remote: $remote"
  dim "Target: $STORE_DIR"

  if [[ -d "$STORE_DIR/.git" ]]; then
    warn "store/ is already a git repo: $STORE_DIR"
    echo -n "  Re-clone and overwrite? [y/N] "
    read -r confirm
    [[ "$confirm" =~ ^[Yy] ]] || { skip "Cancelled"; exit 0; }
    run rm -rf "$STORE_DIR"
  fi

  run git clone "$remote" "$STORE_DIR"
  info "Cloned store from remote"

  cmd_setup
}
