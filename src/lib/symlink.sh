# symlink.sh — Symlink management utilities

ensure_dir() {
  local dir="$1" desc="$2"
  if [[ ! -d "$dir" ]]; then
    run mkdir -p "$dir"
    run touch "$dir/.gitkeep"
    info "Created $desc: $dir"
  fi
}

ensure_file() {
  local filepath="$1" desc="$2"
  if [[ ! -f "$filepath" ]]; then
    skip "Missing file: $desc ($filepath — create manually)"
  else
    skip "File exists: $desc"
  fi
}

ensure_symlink() {
  local target="$1" link_path="$2" desc="$3"
  if [[ -L "$link_path" ]]; then
    local current
    current=$(readlink "$link_path")
    if [[ "$current" == "$target" ]]; then
      skip "Symlink already correct: $desc"
      return
    fi
    run rm "$link_path"
    link "Replaced symlink: $desc"
  elif [[ -e "$link_path" ]]; then
    run rm -rf "$link_path"
    link "Replaced existing path: $desc"
  fi
  if ! ${DRY_RUN:-false}; then
    ln -s "$target" "$link_path"
  fi
  link "Symlink: $desc"
}

ensure_external_symlink() {
  local target="$1" link_path="$2" desc="$3"
  local expanded_link="${link_path/#\~/$HOME}"
  local expanded_target="${target/#\~/$HOME}"

  if [[ -L "$expanded_link" ]]; then
    local current
    current=$(readlink "$expanded_link")
    if [[ "$current" == "$expanded_target" ]]; then
      skip "External symlink already correct: $desc"
      return
    fi
    run rm "$expanded_link"
    link "Replaced external symlink: $desc"
  elif [[ -e "$expanded_link" ]]; then
    backup "$expanded_link" "$desc config"
    if ${DRY_RUN:-false}; then
      skip "(would symlink) $expanded_link → $expanded_target"
    else
      ln -s "$expanded_target" "$expanded_link"
      link "External symlink: $desc ($expanded_link)"
    fi
  else
    if ${DRY_RUN:-false}; then
      skip "(would symlink) $expanded_link → $expanded_target"
    else
      mkdir -p "$(dirname "$expanded_link")"
      ln -s "$expanded_target" "$expanded_link"
      link "External symlink: $desc ($expanded_link)"
    fi
  fi
}

remove_symlink() {
  local link_path="$1" desc="$2"
  local expanded="${link_path/#\~/$HOME}"
  if [[ -L "$expanded" ]]; then
    run rm "$expanded"
    link "Removed symlink: $desc"
  elif [[ -e "$expanded" ]]; then
    warn "Not a symlink, skipping: $expanded"
  else
    skip "No symlink to remove: $desc"
  fi
}
