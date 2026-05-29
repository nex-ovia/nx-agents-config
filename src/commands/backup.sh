# backup.sh — Backup tool data directories

cmd_backup() {
  local tool="${1:-}"
  if [[ -z "$tool" ]]; then
    err "Usage: nx-agents-config backup <tool-name>"
    echo ""
    echo "Available tools:"
    while IFS= read -r t; do
      local desc
      desc=$(tool_desc "$t")
      local data
      data=$(tool_data "$t")
      if [[ -n "$data" ]]; then
        echo "  $t  ($desc)  data: $data"
      else
        echo "  $t  ($desc)  (no separate data dir — config in store)"
      fi
    done < <(tool_names)
    exit 1
  fi

  if ! tool_exists "$tool" >/dev/null; then
    err "Unknown tool: $tool"
    echo "Run 'nx-agents-config backup' to list available tools."
    exit 1
  fi

  local data_dir
  data_dir=$(tool_data "$tool")
  local expanded_data="${data_dir/#\~/$HOME}"

  if [[ -z "$data_dir" ]]; then
    err "Tool '$tool' has no separate data directory — its config is already in store/"
    echo "Define 'data' in nx-agents.toml to add backup support."
    exit 1
  fi

  if [[ ! -d "$expanded_data" ]]; then
    err "Data directory not found: $expanded_data"
    exit 1
  fi

  local bak_dir="${HOME}/.${tool}.bak.${TIMESTAMP}"
  heading "Backing up $tool data"
  dim "Source: $expanded_data"
  dim "Backup: $bak_dir"

  if ${DRY_RUN:-false}; then
    skip "(would backup) $expanded_data → $bak_dir"
  else
    run mkdir -p "$bak_dir"
    run cp -a "$expanded_data"/. "$bak_dir"/ 2>/dev/null || run cp -R "$expanded_data"/. "$bak_dir"/
    info "Backup created: $bak_dir"
  fi
}
