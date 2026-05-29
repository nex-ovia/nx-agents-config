# update.sh — Reconcile filesystem to match merged config

cmd_update() {
  heading "Updating from merged config..."
  dim "Store: $STORE_DIR"

  # 1. Shared directories
  heading "Ensuring shared resources"
  while IFS= read -r k; do
    local rel_path
    rel_path=$(shared_path "$k")
    ensure_dir "$REPO_DIR/$rel_path" "shared/$k ($(shared_desc "$k"))"
    ensure_dir "$STORE_DIR/$rel_path" "store/shared/$k ($(shared_desc "$k"))"
  done < <(shared_keys)

  # 2. Tools
  while IFS= read -r t; do
    local desc ext tool_dir
    desc=$(tool_desc "$t")
    ext=$(tool_external "$t")
    tool_dir="$STORE_DIR/$t"

    heading "Tool: $t ($desc)"
    check_deps "$t" || true
    ensure_dir "$tool_dir" "$t (store/)"

    # Internal symlinks
    local int_count
    int_count=$(tool_int_count "$t")
    if [[ "$int_count" != "0" ]]; then
      for i in $(seq 0 $((int_count - 1))); do
        local from to idesc link_path target_path
        from=$(tool_int_from "$t" "$i")
        to=$(tool_int_to "$t" "$i")
        idesc=$(tool_int_desc "$t" "$i")
        link_path="$tool_dir/$from"
        target_path="$STORE_DIR/$to"
        ensure_symlink "$target_path" "$link_path" "$idesc"
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

    # External symlink
    ensure_external_symlink "$tool_dir" "$ext" "$desc"
  done < <(tool_names)

  # 3. Orphan detection — store/ subdirs not in TOML
  heading "Orphan detection (store/)"
  local known=("shared" ".git" ".gitkeep" "config.toml")
  while IFS= read -r t; do known+=("$t"); done < <(tool_names)

  if [[ -d "$STORE_DIR" ]]; then
    for entry in "$STORE_DIR"/*; do
      local base
      base=$(basename "$entry")
      [[ -d "$entry" ]] || continue
      local is_known=false
      for k in "${known[@]}"; do
        [[ "$base" == "$k" ]] && { is_known=true; break; }
      done
      $is_known && continue
      move_to_removed "$entry" "Not in TOML"
    done
  fi

  echo ""
  info "Update complete!"
}
