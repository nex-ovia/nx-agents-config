#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/nex-ovia/nx-agents-config"
TAR_URL="${REPO_URL}/archive/main.tar.gz"
INSTALL_DIR="${HOME}/.nx-agents-config"
CLI_SYMLINK="${HOME}/.local/bin/nx-agents-config"

# ---------------------------------------------------------------------------
# Colors (self-contained for bootstrap — same scheme as the tool)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  if command -v tput &>/dev/null; then
    GREEN=$(tput setaf 2); CYAN=$(tput setaf 6)
    YELLOW=$(tput setaf 3); RED=$(tput setaf 1)
    BOLD=$(tput bold); DIM=$(tput dim 2>/dev/null || printf ''); NC=$(tput sgr0)
  else
    GREEN='\033[0;32m'; CYAN='\033[0;36m'
    YELLOW='\033[1;33m'; RED='\033[0;31m'
    BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
  fi
  if [[ "$TERM" == *"linux"* || "$LANG" == *"C"* || "$LANG" == *"POSIX"* ]]; then
    ICON_OK="${GREEN}[ok]${NC}"; ICON_ERR="${RED}[err]${NC}"; ICON_LINK="${CYAN}->${NC}"; ICON_WARN="${YELLOW}[!]${NC}"
  else
    ICON_OK="${GREEN}${NC}"; ICON_ERR="${RED}${NC}"; ICON_LINK="${CYAN}${NC}"; ICON_WARN="${YELLOW}${NC}"
  fi
else
  GREEN=''; CYAN=''; YELLOW=''; RED=''; BOLD=''; DIM=''; NC=''
  ICON_OK="[ok]"; ICON_ERR="[err]"; ICON_LINK="->"; ICON_WARN="[!]"
fi

info()    { printf "  %s %s\n" "$ICON_OK" "$1"; }
link()    { printf "  %s %s\n" "$ICON_LINK" "$1"; }
warn()    { printf "  %s %s\n" "$ICON_WARN" "$1"; }
err()     { printf "  %s %s\n" "$ICON_ERR" "$1" >&2; exit 1; }
dim()     { printf "%s%s%s\n" "${DIM}" "$1" "${NC}"; }
heading() { printf "\n%s%s%s\n" "$BOLD" "$1" "$NC"; }

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
RUN_SETUP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --setup) RUN_SETUP=true; shift ;;
    --help|-h)
      echo "Usage: curl -fsSL ${REPO_URL}/raw/main/bootstrap.sh | bash [-s -- [options]]"
      echo ""
      echo "Options:"
      echo "  --dir <path>    Install to custom path (default: ~/.nx-agents-config)"
      echo "  --setup         Also run 'nx-agents-config setup' after install"
      echo "  --help          Show this help"
      exit 0
      ;;
    *) err "Unknown option: $1";;
  esac
done

# ---------------------------------------------------------------------------
heading "nx-agents-config — Bootstrap Install"

# Prerequisites
heading "Checking prerequisites"
for cmd in curl python3 jq; do
  if command -v "$cmd" &>/dev/null; then
    info "$cmd found: $(command -v "$cmd")"
  else
    err "$cmd is required. Install it and re-run."
  fi
done

# Warn if git is missing (needed later for store/ sync)
if ! command -v git &>/dev/null; then
  warn "git not found — store/ sync will not work until git is installed"
fi

# Download template
heading "Downloading template"
if [[ -d "$INSTALL_DIR" ]] && [[ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
  warn "Directory already exists and is not empty: $INSTALL_DIR"
  echo -n "  Overwrite existing files? [y/N] "
  read -r overwrite
  if [[ "$overwrite" =~ ^[Yy] ]]; then
    curl -fsSL "$TAR_URL" | tar xz --strip=1 -C "$INSTALL_DIR"
    info "Template extracted to $INSTALL_DIR"
  else
    skip "Using existing files"
  fi
else
  mkdir -p "$INSTALL_DIR"
  curl -fsSL "$TAR_URL" | tar xz --strip=1 -C "$INSTALL_DIR"
  info "Template extracted to $INSTALL_DIR"
fi

# Create CLI symlink
heading "Installing CLI"
mkdir -p "$(dirname "$CLI_SYMLINK")"
if [[ -L "$CLI_SYMLINK" ]]; then
  current=$(readlink "$CLI_SYMLINK")
  if [[ "$current" == "$INSTALL_DIR/bin/nx-agents-config" ]]; then
    info "CLI symlink already correct"
  else
    ln -sf "$INSTALL_DIR/bin/nx-agents-config" "$CLI_SYMLINK"
    link "Updated CLI symlink → $CLI_SYMLINK"
  fi
elif [[ -f "$CLI_SYMLINK" ]]; then
  err "$CLI_SYMLINK exists but is not a symlink — remove it manually"
else
  ln -s "$INSTALL_DIR/bin/nx-agents-config" "$CLI_SYMLINK"
  link "Created CLI symlink → $CLI_SYMLINK"
fi

if ! echo "$PATH" | tr ':' '\n' | grep -q "$(dirname "$CLI_SYMLINK")"; then
  dim "  Note: Add ~/.local/bin to your PATH in ~/.zshrc or ~/.bashrc:"
  dim "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# Verify TOML
heading "Verifying configuration"
if python3 -c "
import tomllib
with open('$INSTALL_DIR/nx-agents.toml', 'rb') as f:
    tomllib.load(f)
print('  ${ICON_OK} nx-agents.toml is valid')
" 2>/dev/null; then
  :
else
  warn "nx-agents.toml could not be parsed"
fi

# Run setup if requested
if [[ "${RUN_SETUP:-false}" == "true" ]]; then
  heading "Running setup"
  bash "$INSTALL_DIR/bin/nx-agents-config" setup
fi

# Next steps
heading "Install complete!"
echo ""
echo "  Next steps:"
echo "  ${CYAN}1.${NC} Run setup to create store/ and symlinks:"
echo "     ${DIM}nx-agents-config setup${NC}"
echo "  ${CYAN}2.${NC} Preview your config:"
echo "     ${DIM}nx-agents-config tree${NC}"
echo "  ${CYAN}3.${NC} Keep the tool updated:"
echo "     ${DIM}nx-agents-config update-tool${NC}"
echo "  ${CYAN}4.${NC} Sync your store/ data (your private git repo):"
echo "     ${DIM}nx-agents-config sync${NC}"
echo "  ${CYAN}5.${NC} Star the repo if you find it useful:"
echo "     ${DIM}https://github.com/nex-ovia/nx-agents-config${NC}"
