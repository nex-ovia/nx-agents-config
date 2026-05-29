# update-tool.sh — Update the nx-agents-config tool from GitHub template
# Downloads latest tarball, rsyncs over existing files (never touches store/)

cmd_update_tool() {
  heading "Updating nx-agents-config tool..."
  dim "Tool dir: $REPO_DIR"
  dim "Store dir: $STORE_DIR"

  for cmd in curl rsync; do
    if ! command -v "$cmd" &>/dev/null; then
      err "$cmd is required for update-tool"
      exit 1
    fi
  done

  local tar_url="https://github.com/nex-ovia/nx-agents-config/archive/main.tar.gz"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  info "Downloading latest template..."
  if ! curl -fsSL "$tar_url" | tar xz --strip=1 -C "$tmp_dir" 2>/dev/null; then
    rm -rf "$tmp_dir"
    err "Failed to download template. Check your internet connection."
    exit 1
  fi
  info "Downloaded and extracted to temporary directory"

  # Check version
  local new_version old_version
  new_version=$(grep -E '^version\s*=' "$tmp_dir/nx-agents.toml" 2>/dev/null | head -1 | sed 's/.*= *"//;s/"$//' || echo "unknown")
  old_version=$(grep -E '^version\s*=' "$REPO_DIR/nx-agents.toml" 2>/dev/null | head -1 | sed 's/.*= *"//;s/"$//' || echo "unknown")

  if [[ "$new_version" == "$old_version" ]]; then
    skip "Already at version $old_version — no update needed"
    rm -rf "$tmp_dir"
    return
  fi

  info "Updating from $old_version → $new_version..."

  if ${DRY_RUN:-false}; then
    skip "(would rsync) new template over $REPO_DIR, excluding store/"
    info "Changes in new version:"
    diff -rq "$REPO_DIR" "$tmp_dir" 2>/dev/null | grep -v 'Only in.*store/' || skip "No changes detected"
  else
    mkdir -p "$REPO_DIR"
    rsync -a --delete --exclude='/store/' "$tmp_dir/" "$REPO_DIR/"
    info "Tool updated to version $new_version (store/ data was NOT touched)"
  fi

  rm -rf "$tmp_dir"
}
