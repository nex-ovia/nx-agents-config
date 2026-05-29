# project.sh — Project management in store/

cmd_project() {
  local subcmd="${1:-help}"
  shift 2>/dev/null || true

  case "$subcmd" in
    add)
      local name="${1:-}"
      if [[ -z "$name" ]]; then
        err "Usage: nx-agents-config project add <name>"
        exit 1
      fi
      if ! echo "$name" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9_-]+$'; then
        err "Project name must be alphanumeric with hyphens/underscores"
        exit 1
      fi

      local proj_dir="$STORE_DIR/shared/projects/$name"
      heading "Adding project: $name"

      if [[ -d "$proj_dir" ]]; then
        skip "Project already exists: $name"
        return
      fi

      run mkdir -p "$proj_dir"
      info "Created: $proj_dir"

      # Create template files
      cat > "$proj_dir/context.md" << 'EOF'
# Project: <name>
## Goals
## Architecture
## Notes
EOF
      info "Created: context.md"

      cat > "$proj_dir/sessions.toml" << 'EOF'
[sessions]
# Recent session IDs, newest first
recent = []
EOF
      info "Created: sessions.toml"

      cat > "$proj_dir/meta.toml" << 'EOF'
[meta]
created = "<date>"
description = ""
tags = []
EOF
      info "Created: meta.toml"
      ;;

    list)
      heading "Projects"
      local proj_base="$STORE_DIR/shared/projects"
      if [[ ! -d "$proj_base" ]]; then
        skip "No projects directory yet"
        return
      fi
      local count=0
      for p in "$proj_base"/*/; do
        [[ -d "$p" ]] || continue
        count=$((count + 1))
        local name
        name=$(basename "$p")
        local desc=""
        if [[ -f "$p/meta.toml" ]]; then
          desc=$(grep -E '^description\s*=' "$p/meta.toml" 2>/dev/null | head -1 | sed 's/.*= *"//;s/"$//')
        fi
        echo "  ${CYAN}•${NC} $name  $(dim "${desc}")"
      done
      if [[ "$count" -eq 0 ]]; then
        skip "No projects found"
      fi
      ;;

    help|--help|-h|"")
      echo "Usage: nx-agents-config project <command>"
      echo ""
      echo "Commands:"
      echo "  add <name>     Create a new project in store/"
      echo "  list           List projects"
      ;;

    *)
      err "Unknown project command: $subcmd"
      echo "Usage: nx-agents-config project help"
      exit 1
      ;;
  esac
}
