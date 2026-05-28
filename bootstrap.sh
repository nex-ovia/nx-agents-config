#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/nex-ovia/nx-agents-config"
INSTALL_DIR="${HOME}/nx-agents-config"
CLI_SYMLINK="${HOME}/.local/bin/nx-agents-config"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "  ${GREEN}✓${NC} $1"; }
link()  { echo -e "  ${CYAN}→${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()   { echo -e "  ${RED}✗${NC} $1"; exit 1; }
dim()   { echo -e "${YELLOW}$1${NC}"; }

heading() { echo -e "\n${BOLD}$1${NC}"; }

usage() {
  echo "Usage: curl -fsSL ${REPO_URL}/raw/main/bootstrap.sh | bash [-s -- [options]]"
  echo ""
  echo "Options:"
  echo "  --dir <path>    Install to custom path (default: ~/nx-agents-config)"
  echo "  --setup         Also run 'nx-agents-config setup' after install"
  echo "  --help          Show this help"
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --setup) RUN_SETUP=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) err "Unknown option: $1";;
  esac
done

heading "nx-agents-config — Bootstrap Install"

# Prerequisites
heading "Checking prerequisites"
for cmd in git python3 jq; do
  if command -v "$cmd" &>/dev/null; then
    info "$cmd found: $(command -v "$cmd")"
  else
    err "$cmd is required. Install it and re-run."
  fi
done

# Clone
heading "Cloning repository"
if [[ -d "$INSTALL_DIR" ]]; then
  warn "Directory already exists: $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Existing git repo found — pulling latest"
    (cd "$INSTALL_DIR" && git pull --ff-only)
  else
    warn "Not a git repo — skipping clone. Remove the dir and re-run for a fresh install."
  fi
else
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  info "Cloned to $INSTALL_DIR"
fi

# CLI symlink
heading "Installing CLI"
mkdir -p "$(dirname "$CLI_SYMLINK")"
if [[ -L "$CLI_SYMLINK" ]]; then
  current=$(readlink "$CLI_SYMLINK")
  if [[ "$current" == "$INSTALL_DIR/setup.sh" ]]; then
    info "CLI symlink already correct"
  else
    ln -sf "$INSTALL_DIR/setup.sh" "$CLI_SYMLINK"
    link "Updated CLI symlink → $CLI_SYMLINK"
  fi
elif [[ -f "$CLI_SYMLINK" ]]; then
  err "$CLI_SYMLINK exists but is not a symlink — remove it manually"
else
  ln -s "$INSTALL_DIR/setup.sh" "$CLI_SYMLINK"
  link "Created CLI symlink → $CLI_SYMLINK"
fi

if ! echo "$PATH" | tr ':' '\n' | grep -q "$(dirname "$CLI_SYMLINK")"; then
  dim "  Note: Add $(dirname "$CLI_SYMLINK") to your PATH in ~/.zshrc or ~/.bashrc:"
  dim "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Verify TOML
heading "Verifying configuration"
if python3 -c "
import tomllib
with open('$INSTALL_DIR/nx-agents.toml', 'rb') as f:
    tomllib.load(f)
print('  ${GREEN}✓${NC} nx-agents.toml is valid')
" 2>/dev/null; then
  :
else
  warn "nx-agents.toml could not be parsed"
fi

# Run setup if requested
if [[ "${RUN_SETUP:-false}" == "true" ]]; then
  heading "Running setup"
  bash "$INSTALL_DIR/setup.sh" setup
fi

# Next steps
heading "Install complete!"
echo ""
echo "  Next steps:"
echo "  ${CYAN}1.${NC} Run setup to create symlinks:"
echo "     ${DIM}nx-agents-config setup${NC}"
echo "  ${CYAN}2.${NC} Preview your config:"
echo "     ${DIM}nx-agents-config tree${NC}"
echo "  ${CYAN}3.${NC} Add daily sync to ~/.zshrc:"
echo "     ${DIM}command -v nx-agents-config &>/dev/null && nx-agents-config sync${NC}"
echo "  ${CYAN}4.${NC} Create your first skill:"
echo "     ${DIM}mkdir -p ~/.nx-agents-config/shared/skills/<name>${NC}"
echo "     ${DIM}# then create SKILL.md inside it${NC}"
