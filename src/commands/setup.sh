# setup.sh — Initial setup: scaffold store, merge configs, create symlinks

cmd_setup() {
  heading "Setting up ${CONFIG_NAME}..."
  dim "Timestamp: $TIMESTAMP"
  dim "Store: $STORE_DIR"

  # 1. Ensure store/ exists
  heading "Store directory"
  if [[ ! -d "$STORE_DIR" ]]; then
    run mkdir -p "$STORE_DIR"
    run touch "$STORE_DIR/.gitkeep"
    info "Created store/: $STORE_DIR"
  else
    skip "Store already exists: $STORE_DIR"
  fi

  # 2. Offer git init for store
  if [[ ! -d "$STORE_DIR/.git" ]]; then
    if ${DRY_RUN:-false}; then
      skip "(would prompt for git init)"
    else
      echo ""
      echo -n "  Initialize store as a git repo? [Y/n] "
      read -r init_git
      if [[ -z "$init_git" || "$init_git" =~ ^[Yy] ]]; then
        run git -C "$STORE_DIR" init
        info "Git init'd store/"
        echo "  Enter your store remote URL (e.g., git@github.com:user/nx-agents-config-store.git) [leave empty to skip]:"
        echo -n "  > "
        read -r remote_url
        if [[ -n "$remote_url" ]]; then
          run git -C "$STORE_DIR" remote add origin "$remote_url"
          info "Remote added: $remote_url"

          # If the remote already has commits, offer to restore now
          local remote_head
          remote_head=$(git -C "$STORE_DIR" ls-remote origin HEAD 2>/dev/null | cut -f1 || echo "")
          if [[ -n "$remote_head" ]]; then
            echo ""
            echo -n "  Remote has existing store data. Restore it now? [Y/n] "
            read -r do_restore
            if [[ -z "$do_restore" || "$do_restore" =~ ^[Yy] ]]; then
              run git -C "$STORE_DIR" fetch origin
              local restore_branch
              restore_branch=$(git -C "$STORE_DIR" ls-remote --heads origin \
                | head -1 | awk '{print $2}' | sed 's|refs/heads/||')
              run git -C "$STORE_DIR" checkout -b "$restore_branch" "origin/$restore_branch"
              info "Restored store from remote (branch: $restore_branch)"
            fi
          fi
        fi
      fi
    fi
  fi

  # 3. Create default store/config.toml if missing
  local user_config="$STORE_DIR/config.toml"
  if [[ ! -f "$user_config" ]]; then
    if ${DRY_RUN:-false}; then
      skip "(would create) store/config.toml"
    else
      cat > "$user_config" << 'EOF'
# config.toml — User overrides for nx-agents-config
# This file is merged with nx-agents.toml (tool defaults).
# Entries here override defaults with the same name.
#
# Examples:
#   [[tool]]
#   name = "my-tool"
#   desc = "My custom agent"
#   external = "~/.config/my-tool"
EOF
      info "Created: $user_config"
    fi
  else
    skip "User config exists: $user_config"
  fi

  # 4. Shared directories
  heading "Shared resources"
  while IFS= read -r k; do
    local rel_path
    rel_path=$(shared_path "$k")
    ensure_dir "$NX_AGENTS_HOME/$rel_path" "shared/$k ($(shared_desc "$k"))"
    # Also ensure in store/
    ensure_dir "$STORE_DIR/$rel_path" "store/shared/$k ($(shared_desc "$k"))"
  done < <(shared_keys)

  # 5. Tools
  while IFS= read -r t; do
    local desc
    desc=$(tool_desc "$t")
    local ext
    ext=$(tool_external "$t")
    local tool_dir="$STORE_DIR/$t"

    heading "Tool: $t ($desc)"
    check_deps "$t" || true
    ensure_dir "$tool_dir" "$t directory (store/)"

    # Tool-level .gitignore
    if ! ${DRY_RUN:-false}; then
      local gi_file="$tool_dir/.gitignore"
      if [[ ! -f "$gi_file" ]]; then
        local gi_entries=()
        while IFS= read -r entry; do
          [[ -n "$entry" ]] && gi_entries+=("$entry")
        done < <(tool_gitignore "$t")
        if [[ ${#gi_entries[@]} -gt 0 ]]; then
          printf '%s\n' "${gi_entries[@]}" > "$gi_file"
          info "Created .gitignore for $t"
        fi
      fi
    fi

    # Internal symlinks within tool dir
    local int_count
    int_count=$(tool_int_count "$t")
    if [[ "$int_count" != "0" ]]; then
      for i in $(seq 0 $((int_count - 1))); do
        local from to idesc link_path target_path
        from=$(tool_int_from "$t" "$i")
        to=$(tool_int_to "$t" "$i")
        idesc=$(tool_int_desc "$t" "$i")
        link_path="$tool_dir/$from"
        ensure_symlink "$to" "$link_path" "$idesc"
      done
    fi

    # Config files
    local f_count
    f_count=$(tool_file_count "$t")
    if [[ "$f_count" != "0" ]]; then
      for i in $(seq 0 $((f_count - 1))); do
        local fpath fdesc
        fpath=$(tool_file_path "$t" "$i")
        fdesc=$(tool_file_desc "$t" "$i")
        ensure_file "$tool_dir/$fpath" "$fdesc"
      done
    fi

    # External symlink (tool config dir → store/toolname/)
    ensure_external_symlink "$tool_dir" "$ext" "$desc"

    # External dirs (additional external paths → store subdir, with .gitignore)
    local ed_count
    ed_count=$(tool_external_dir_count "$t")
    if [[ "$ed_count" != "0" ]]; then
      for i in $(seq 0 $((ed_count - 1))); do
        local ed_path ed_sp ed_desc
        ed_path=$(tool_external_dir_path "$t" "$i")
        ed_sp=$(tool_external_dir_store_path "$t" "$i")
        ed_desc=$(tool_external_dir_desc "$t" "$i")
        local ed_store_subdir="$tool_dir/$ed_sp"
        local gi_entries=()
        while IFS= read -r entry; do
          [[ -n "$entry" ]] && gi_entries+=("$entry")
        done < <(tool_external_dir_gitignore "$t" "$i")
        ensure_external_dir_symlink "$ed_store_subdir" "$ed_path" "$ed_desc" \
          "${gi_entries[@]+"${gi_entries[@]}"}"
      done
    fi

    # External files (backup to store + symlink)
    local ef_count
    ef_count=$(tool_external_file_count "$t")
    if [[ "$ef_count" != "0" ]]; then
      for i in $(seq 0 $((ef_count - 1))); do
        local ef_path ef_desc store_path store_name
        ef_path=$(tool_external_file_path "$t" "$i")
        ef_desc=$(tool_external_file_desc "$t" "$i")
        store_name=$(basename "${ef_path/#\~/$HOME}")
        store_path="$tool_dir/$store_name"
        ensure_external_file_symlink "$store_path" "$ef_path" "$ef_desc"
      done
    fi
  done < <(tool_names)

    # 6. CLI symlink
  heading "CLI entry point"
  local script_path
  script_path="$(realpath_safe "${BASH_SOURCE[0]}")"
  local cli_link="$HOME/.local/bin/nx-agents-config"
  ensure_external_symlink "$script_path" "$cli_link" "CLI binary"

  if ! echo "$PATH" | tr ':' '\n' | grep -q "$HOME/.local/bin"; then
    dim "  Note: Add ~/.local/bin to your PATH:"
    dim "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi

  dim "  Star us: https://github.com/nex-ovia/nx-agents-config"
  echo ""
  info "Setup complete! Run '${BOLD}nx-agents-config tree${NC}' to verify."
}
