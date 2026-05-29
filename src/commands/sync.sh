# sync.sh — Git sync operations on the user's store/ repo

cmd_sync() {
  heading "Syncing store/ data..."
  dim "Store: $STORE_DIR"

  if [[ ! -d "$STORE_DIR/.git" ]]; then
    warn "store/ is not a git repository."
    echo -n "  Initialize now? [Y/n] "
    read -r init_repo
    if [[ -z "$init_repo" || "$init_repo" =~ ^[Yy] ]]; then
      run git -C "$STORE_DIR" init
      info "Git repo initialized in store/"
      echo -n "  Enter remote URL (or leave empty): "
      read -r remote_url
      if [[ -n "$remote_url" ]]; then
        run git -C "$STORE_DIR" remote add origin "$remote_url"
        info "Remote added: $remote_url"
      fi
    else
      skip "Cancelled"
    fi
    return
  fi

  (
    cd "$STORE_DIR"

    # Fetch
    git fetch --quiet 2>/dev/null || true

    # Show status
    local status_output
    status_output=$(git status --short 2>/dev/null || true)
    if [[ -n "$status_output" ]]; then
      heading "Uncommitted changes"
      echo "$status_output"
    else
      skip "Working tree clean"
    fi

    # Check for upstream
    local remote
    remote=$(git remote 2>/dev/null || echo "")
    if [[ -n "$remote" ]]; then
      local behind
      behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
      if [[ "$behind" != "0" ]]; then
        info "Remote has $behind new commit(s)"
        echo -n "  Pull? [Y/n] "
        read -r do_pull
        if [[ -z "$do_pull" || "$do_pull" =~ ^[Yy] ]]; then
          run git pull --ff-only
          info "Pulled updates"
        fi
      fi
    fi

    # Offer to commit and push
    local has_changes
    has_changes=$(git status --porcelain 2>/dev/null || true)
    if [[ -n "$has_changes" ]]; then
      echo ""
      echo -n "  Commit and push changes? [y/N] "
      read -r do_commit
      if [[ "$do_commit" =~ ^[Yy] ]]; then
        echo -n "  Commit message: "
        read -r msg
        msg="${msg:-Update store/ config}"
        run git add -A
        run git commit -m "$msg"
        if [[ -n "$remote" ]]; then
          run git push
          info "Pushed to remote"
        fi
      fi
    fi
  )
}
