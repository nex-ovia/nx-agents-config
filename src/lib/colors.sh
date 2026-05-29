# colors.sh — Portable color system (tput + printf)
# Works on macOS, Linux, TTY, and piped output.

if [[ -t 1 ]]; then
  if command -v tput &>/dev/null; then
    GREEN=$(tput setaf 2)
    CYAN=$(tput setaf 6)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    BOLD=$(tput bold)
    DIM=$(tput dim 2>/dev/null || tput setaf 8 2>/dev/null || printf '')
    NC=$(tput sgr0)
  else
    GREEN='\033[0;32m'; CYAN='\033[0;36m'
    YELLOW='\033[1;33m'; RED='\033[0;31m'
    BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
  fi

  if [[ "$TERM" == *"linux"* || "$LANG" == *"C"* || "$LANG" == *"POSIX"* ]]; then
    ICON_OK="${GREEN}[ok]${NC}";   ICON_WARN="${YELLOW}[!]${NC}"
    ICON_ERR="${RED}[err]${NC}";   ICON_SKIP="${YELLOW}[-]${NC}"; ICON_LINK="${CYAN}->${NC}"
  else
    ICON_OK="${GREEN}${NC}"; ICON_WARN="${YELLOW}${NC}"
    ICON_ERR="${RED}${NC}"; ICON_SKIP="${YELLOW}${NC}"; ICON_LINK="${CYAN}${NC}"
  fi
else
  GREEN=''; CYAN=''; YELLOW=''; RED=''; BOLD=''; DIM=''; NC=''
  ICON_OK="[ok]"; ICON_WARN="[!]"; ICON_ERR="[err]"
  ICON_SKIP="[-]"; ICON_LINK="->"
fi

info()    { printf "  %s %s\n" "$ICON_OK" "$1"; }
link()    { printf "  %s %s\n" "$ICON_LINK" "$1"; }
skip()    { printf "  %s %s\n" "$ICON_SKIP" "$1"; }
err()     { printf "  %s %s\n" "$ICON_ERR" "$1" >&2; }
warn()    { printf "  %s %s\n" "$ICON_WARN" "$1"; }
heading() { printf "\n%s%s%s\n" "$BOLD" "$1" "$NC"; }
dim()     { printf "%s%s%s\n" "$DIM" "$1" "$NC"; }
