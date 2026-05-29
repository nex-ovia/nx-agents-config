# backup.sh — Backup and restore utilities

backup() {
  local src="$1" label="$2"
  if [[ -e "$src" ]]; then
    local bak="${src}.bak.${TIMESTAMP}"
    if ${DRY_RUN:-false}; then
      skip "(would backup) $label → $bak"
    else
      mv "$src" "$bak"
      link "Backed up $label → $bak"
    fi
  fi
}

BACKUP_DIR=""

backup_store() {
  BACKUP_DIR="${HOME}/.nx-agents-config.store.bak.${TIMESTAMP}"
  if [[ -d "$STORE_DIR" ]] && [[ -n "$(ls -A "$STORE_DIR" 2>/dev/null)" ]]; then
    if ${DRY_RUN:-false}; then
      skip "(would backup) store/ → $BACKUP_DIR"
    else
      cp -a "$STORE_DIR" "$BACKUP_DIR" 2>/dev/null || cp -R "$STORE_DIR" "$BACKUP_DIR"
      info "Store backed up → $BACKUP_DIR"
    fi
  else
    skip "No store/ data to backup"
    BACKUP_DIR=""
  fi
}

move_to_removed() {
  local path="$1" reason="$2"
  local dest="$REMOVED_DIR/$(basename "$path")"
  if ${DRY_RUN:-false}; then
    skip "(would move to .removed/) $path — $reason"
  else
    mkdir -p "$REMOVED_DIR"
    mv "$path" "$dest"
    link "Moved to .removed/: $path — $reason"
  fi
}
