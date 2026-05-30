# sync.sh — Non-interactive git sync on store/ (auto commit + pull + push)

cmd_sync() {
  local msg="${1:-}"
  heading "Syncing store/..."
  dim "Store: $STORE_DIR"

  if [[ ! -d "$STORE_DIR/.git" ]]; then
    err "store/ is not a git repository. Run 'nx-agents-config setup' first."
    exit 1
  fi

  (
    cd "$STORE_DIR"

    # WAL checkpoint for opencode.db to ensure committed DB is consistent
    local db="$STORE_DIR/opencode/userdata/opencode.db"
    if [[ -f "$db" ]]; then
      sqlite3 "$db" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    fi

    local remote
    remote=$(git remote 2>/dev/null | head -1 || echo "")

    # Commit local changes first so pull sees a clean tree
    local has_changes
    has_changes=$(git status --porcelain 2>/dev/null || true)
    if [[ -n "$has_changes" ]]; then
      local commit_msg
      commit_msg="${msg:-sync: $(date +%Y-%m-%d.%H%M%S)}"
      run git add -A
      run git commit -m "$commit_msg"
      info "Committed: $commit_msg"
    else
      skip "Working tree clean — nothing to commit"
    fi

    # Pull with rebase to handle both fast-forward and diverged histories
    if [[ -n "$remote" ]]; then
      git fetch --quiet origin 2>/dev/null || true
      local behind
      behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
      if [[ "$behind" != "0" ]]; then
        if git rebase --quiet origin/HEAD 2>/dev/null; then
          info "Pulled $behind commit(s) from remote"
        else
          git rebase --abort 2>/dev/null || true
          err "Rebase conflict — resolve manually then sync again:"
          err "  cd $STORE_DIR && git pull --rebase"
          exit 1
        fi
      fi
    fi

    # Push if remote configured (fetch first to refresh tracking refs)
    if [[ -n "$remote" ]]; then
      git fetch --quiet origin 2>/dev/null || true
      if run git push origin HEAD:main; then
        info "Pushed to remote"
      else
        warn "Push failed — check remote connectivity"
        exit 1
      fi
    else
      skip "No remote configured — local commit only"
    fi
  )
}
