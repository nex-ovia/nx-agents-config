# tree.sh — Display configured directory tree

cmd_tree() {
  echo ""
  heading "${CONFIG_NAME}/  (~/.nx-agents-config)"

  echo "├── store/    $(dim '[your data — gitignored, separate git remote]')"

  # shared sections
  echo "├── shared/"
  local keys=()
  while IFS= read -r k; do keys+=("$k"); done < <(shared_keys)
  local last_idx=$((${#keys[@]} - 1))
  for i in "${!keys[@]}"; do
    local k="${keys[$i]}"
    local branch="├──"
    [[ $i -eq $last_idx ]] && branch="└──"
    echo "│   $branch ${k}/  $(dim "$(shared_desc "$k")")"
  done

  # tools
  local tools=()
  while IFS= read -r t; do tools+=("$t"); done < <(tool_names)
  local t_last=$((${#tools[@]} - 1))
  for ti in "${!tools[@]}"; do
    local t="${tools[$ti]}"
    local desc=$(tool_desc "$t")
    local ext=$(tool_external "$t")
    local is_last=false
    [[ $ti -eq $t_last ]] && is_last=true

    local tbranch="├──"
    $is_last && tbranch="└──"
    echo "$tbranch ${t}/           $(dim "${desc}  (→ ${ext})")"

    # external files
    local efls=()
    while IFS= read -r line; do efls+=("$line"); done < <(tool_external_files_display "$t" 2>/dev/null || true)

    # sub-items (internal symlinks + files + external files + dependencies)
    local ints=()
    while IFS= read -r line; do ints+=("$line"); done < <(tool_internals_display "$t" 2>/dev/null || true)
    local fls=()
    while IFS= read -r line; do fls+=("$line"); done < <(tool_files_display "$t" 2>/dev/null || true)
    local deps_line
    deps_line=$(tool_deps_display "$t" 2>/dev/null || true)

    local sub_items=("${ints[@]}" "${fls[@]}" "${efls[@]}")
    [[ -n "$deps_line" ]] && sub_items+=("$deps_line")
    local s_last=$((${#sub_items[@]} - 1))
    for si in "${!sub_items[@]}"; do
      local sbranch="├──"
      [[ $si -eq $s_last ]] && sbranch="└──"
      if $is_last; then
        echo "    $sbranch ${sub_items[$si]}"
      else
        echo "│   $sbranch ${sub_items[$si]}"
      fi
    done
  done

  # repo files
  echo "├── nx-agents-config  $(dim '[self-contained binary]')"
  echo "├── LICENSE           $(dim '[MIT]')"
  echo "└── README.md         $(dim '[documentation]')"

  # external symlinks
  echo ""
  heading "External symlinks:"
  for t in "${tools[@]}"; do
    local ext=$(tool_external "$t")
    echo "  ${ext}  →  store/${t}/"
  done
  echo "  ~/.local/bin/nx-agents-config  →  nx-agents-config"
}
