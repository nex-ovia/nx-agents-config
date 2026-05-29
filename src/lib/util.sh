# util.sh — Shared utility functions

realpath_safe() {
  local path="$1"
  while [[ -L "$path" ]]; do
    path="$(readlink "$path")"
  done
  cd "$(dirname "$path")" 2>/dev/null && echo "$(pwd -P)/$(basename "$path")"
}

run() {
  if ${DRY_RUN:-false}; then
    skip "(would run) $*"
  else
    "$@"
  fi
}

check_deps() {
  local tool="$1" missing=0
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    if command -v "$dep" &>/dev/null; then
      info "Dependency '$dep' found for '$tool'"
    else
      warn "Missing dependency '$dep' for '$tool'"
      missing=1
    fi
  done < <(tool_dependencies "$tool")
  return $missing
}
