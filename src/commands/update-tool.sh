# update-tool.sh — Update the nx-agents-config tool (never touches store/)

cmd_update_tool() {
  heading "Updating nx-agents-config tool..."
  dim "Tool repo: $REPO_DIR"

  if [[ ! -d "$REPO_DIR/.git" ]]; then
    err "Tool repo is not a git repository: $REPO_DIR"
    exit 1
  fi

  local remote
  remote=$(git -C "$REPO_DIR" remote 2>/dev/null || echo "")
  if [[ -z "$remote" ]]; then
    warn "No git remote configured for tool repo"
    exit 1
  fi

  (
    cd "$REPO_DIR"
    git fetch --quiet 2>/dev/null || true
    local behind
    behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
    if [[ "$behind" != "0" ]]; then
      info "Pulling $behind new commits (store/ data will NOT be touched)..."
      if ${DRY_RUN:-false}; then
        skip "(would pull) git pull --ff-only"
      else
        git pull --ff-only
        info "Tool updated successfully."
      fi
    else
      skip "Already up to date"
    fi
  )
}
