# tool.sh — Tool management (adds to store/config.toml)

cmd_tool() {
  local subcmd="${1:-help}"
  shift 2>/dev/null || true

  case "$subcmd" in
    add)
      local name="${1:-}"
      if [[ -z "$name" ]]; then
        err "Usage: nx-agents-config tool add <name>"
        exit 1
      fi
      if ! echo "$name" | grep -qE '^[a-z][a-z0-9_-]+$'; then
        err "Tool name must be lowercase alphanumeric with hyphens/underscores"
        exit 1
      fi
      if [[ -n "$(tool_exists "$name")" ]]; then
        err "Tool '$name' already exists in merged config"
        exit 1
      fi

      heading "Adding tool: $name"

      echo -n "  Description: "
      read -r desc
      desc="${desc:-$name coding agent}"

      echo -n "  External config path (e.g., ~/.config/$name): "
      read -r ext_path
      ext_path="${ext_path:-~/.config/$name}"

      echo -n "  CLI dependencies (comma-separated, e.g. opencode,bun) [empty for none]: "
      read -r deps_input
      deps_input="${deps_input:-}"

      # Append to store/config.toml
      local user_config="$STORE_DIR/config.toml"
      if [[ ! -f "$user_config" ]]; then
        echo "# config.toml — User overrides for nx-agents-config" > "$user_config"
      fi

      {
        echo ""
        echo "[[tool]]"
        echo "name = \"$name\""
        echo "desc = \"$desc\""
        echo "external = \"$ext_path\""
        if [[ -n "$deps_input" ]]; then
          local dep_list=""
          IFS=',' read -ra deps_arr <<< "$deps_input"
          for d in "${deps_arr[@]}"; do
            d="$(echo "$d" | xargs)"
            [[ -n "$dep_list" ]] && dep_list="$dep_list, "
            dep_list="${dep_list}\"$d\""
          done
          echo "dependencies = [$dep_list]"
        fi
        echo ""
        echo "  [[tool.internal]]"
        echo "  from = \"skills\""
        echo "  to = \"../shared/skills\""
        echo "  desc = \"Shared skills\""
      } >> "$user_config"

      info "Added '$name' to store/config.toml"

      # Create tool dir in store/
      local tool_dir="$STORE_DIR/$name"
      ensure_dir "$tool_dir" "$name (store/)"
      ensure_symlink "$STORE_DIR/shared/skills" "$tool_dir/skills" "Shared skills"

      echo ""
      info "Tool '$name' added! Run '${BOLD}nx-agents-config update${NC}' to sync symlinks."
      ;;

    help|--help|-h|"")
      echo "Usage: nx-agents-config tool <command>"
      echo ""
      echo "Commands:"
      echo "  add <name>     Scaffold a new tool in store/config.toml"
      ;;

    *)
      err "Unknown tool command: $subcmd"
      echo "Usage: nx-agents-config tool help"
      exit 1
      ;;
  esac
}
