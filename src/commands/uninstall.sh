# uninstall.sh — Backup store/ and remove everything

cmd_uninstall() {
  heading "Uninstalling nx-agents-config..."
  warn "This will remove all nx-agents-config files and symlinks."
  echo "  Your store/ data will be backed up."
  echo ""
  if ${DRY_RUN:-false}; then
    skip "Dry-run — skipping confirmation"
  else
    echo -n "  Continue? [y/N] "
    read -r confirm
    [[ "$confirm" =~ ^[Yy] ]] || { skip "Cancelled"; exit 0; }
  fi

  # 1. Backup store
  heading "Backing up store/ data"
  backup_store
  local bak_dir="$BACKUP_DIR"

  # 2. Remove external symlinks for tools
  heading "Removing external symlinks"
  while IFS= read -r t; do
    local ext
    ext=$(tool_external "$t")
    remove_symlink "$ext" "$(tool_desc "$t")"
  done < <(tool_names)

  # 3. Remove CLI symlink
  remove_symlink "$HOME/.local/bin/nx-agents-config" "CLI binary"

  # 4. Remove NX_AGENTS_HOME
  heading "Removing tool directory"
  if ${DRY_RUN:-false}; then
    skip "(would remove) $NX_AGENTS_HOME"
  else
    run rm -rf "$NX_AGENTS_HOME"
    info "Removed: $NX_AGENTS_HOME"
  fi

  # 5. Summary
  echo ""
  heading "Uninstall complete!"
  echo ""
  if [[ -n "$bak_dir" ]]; then
    echo "  Your data was backed up to:"
    echo "    ${bak_dir}"
    echo ""
    echo "  To restore:"
    echo "    1. mkdir -p \"$(dirname "$STORE_DIR")\""
    echo "    2. mv ${bak_dir} ${STORE_DIR}"
    echo "    3. Re-install via the install script"
    echo "    4. Run 'nx-agents-config setup'"
  else
    echo "  No store data to restore."
  fi
}
