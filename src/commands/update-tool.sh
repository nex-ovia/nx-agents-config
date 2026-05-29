# update-tool.sh — Self-update the nx-agents-config binary from GitHub raw

cmd_update_tool() {
  heading "Updating nx-agents-config..."
  dim "Binary location: $NX_AGENTS_HOME/nx-agents-config"

  if ! command -v curl &>/dev/null; then
    err "curl is required for update-tool"
    exit 1
  fi

  local bin_url="https://raw.githubusercontent.com/nex-ovia/nx-agents-config/main/nx-agents-config"
  local tmp_file
  tmp_file=$(mktemp)

  info "Downloading latest binary..."
  if ! curl -fsSL -o "$tmp_file" "$bin_url"; then
    rm -f "$tmp_file"
    err "Failed to download. Check your internet connection."
    exit 1
  fi

  chmod +x "$tmp_file"

  local script_path
  script_path="$(realpath_safe "${BASH_SOURCE[0]}")"

  if ! mv "$tmp_file" "$script_path"; then
    rm -f "$tmp_file"
    err "Failed to replace binary at $script_path"
    exit 1
  fi

  info "Updated successfully!"
  dim "Please re-run nx-agents-config for changes to take effect."
}
