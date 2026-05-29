#!/usr/bin/env bash
# gap-test.sh — Identify concrete gaps in nx-agents-config backup/restore flow.
# Runs two simulated machines (A=write, B=restore) inside the container.
# Each gap is printed with its root cause and file location.
set -euo pipefail

REPO="/repo"
OLLAMA_URL="http://ami-lab.nex-ovia.com:11434"
REMOTE_STORE="/tmp/store-remote.git"
HOME_A="/tmp/machine-a"
HOME_B="/tmp/machine-b"
NX_A="$HOME_A/.nx-agents-config"
NX_B="$HOME_B/.nx-agents-config"
BIN_A="$NX_A/nx-agents-config"
BIN_B="$NX_B/nx-agents-config"

GAPS=()

# ── output helpers ────────────────────────────────────────────────────────────
B='\033[1m'; R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'
section() { echo -e "\n${B}══ $1 ══${NC}"; }
ok()      { echo -e "  ${G}✓${NC}  $1"; }
warn()    { echo -e "  ${Y}!${NC}  $1"; }
gap()     {
  local id="$1"; shift
  GAPS+=("$id")
  echo -e "\n  ${R}[GAP-${id}]${NC} $*"
}

# ── Step 0: build binary ──────────────────────────────────────────────────────
section "Building nx-agents-config binary"
bash "$REPO/build.sh" /tmp/nxbin 2>/dev/null
ok "Binary built: $(wc -c < /tmp/nxbin) bytes"

install_nx() {
  local home="$1" nx="$2" bin="$3"
  rm -rf "$home"
  mkdir -p "$home/.local/bin" "$nx"
  cp /tmp/nxbin "$bin" && chmod +x "$bin"
}

# ── Step 1: check Ollama + pick a chat model ──────────────────────────────────
section "Checking Ollama at $OLLAMA_URL"
OLLAMA_OK=false
OLLAMA_MODEL=""
if curl -sf "$OLLAMA_URL/api/tags" --max-time 5 >/dev/null 2>&1; then
  OLLAMA_OK=true
  # Pick first non-embed model for chat
  OLLAMA_MODEL=$(curl -sf "$OLLAMA_URL/api/tags" \
    | python3 -c "
import json,sys
models=[m['name'] for m in json.load(sys.stdin).get('models',[])
        if 'embed' not in m['name']]
print(models[0] if models else '')
" 2>/dev/null || echo "")
  if [[ -n "$OLLAMA_MODEL" ]]; then
    ok "Ollama reachable. Using model: $OLLAMA_MODEL"
  else
    warn "Ollama reachable but no chat model found — skipping live prompt"
    OLLAMA_OK=false
  fi
else
  warn "Ollama unreachable — simulating prompt results"
fi

# ── PHASE A: Machine A — setup → configure → use → backup → sync ─────────────
section "PHASE A: Machine A (first device)"
install_nx "$HOME_A" "$NX_A" "$BIN_A"
git init --bare "$REMOTE_STORE" -q

# A-1: setup with git init + remote
ok "Running setup (git init + remote = $REMOTE_STORE)"
printf 'y\n%s\n' "$REMOTE_STORE" | HOME="$HOME_A" "$BIN_A" setup 2>&1 \
  | grep -E '(✓|->|!)' | head -20 || true

# A-2: write opencode.json into store (accessible via ~/.config/opencode symlink)
OPENCODE_STORE_CONF="$NX_A/store/opencode/opencode.json"
cat > "$OPENCODE_STORE_CONF" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/$OLLAMA_MODEL",
  "provider": {
    "ollama": {
      "url": "$OLLAMA_URL"
    }
  }
}
EOF
ok "Wrote opencode.json → store/opencode/ (model: ollama/$OLLAMA_MODEL)"

# Verify the symlink makes it visible at the canonical path
if [[ -f "$HOME_A/.config/opencode/opencode.json" ]]; then
  ok "Config accessible at ~/.config/opencode/opencode.json (symlink working)"
else
  warn "~/.config/opencode/opencode.json not reachable — symlink may be wrong"
fi

# A-3: run a quick Ollama prompt (directly via API or via opencode binary)
section "Running test prompt"
PROMPT="Respond in exactly one sentence: what is a shell symlink?"
SESSION_ID="gap-test-$(date +%s)"

if command -v opencode >/dev/null 2>&1 && [[ "$OLLAMA_OK" == "true" ]]; then
  ok "opencode binary found — attempting headless prompt"
  RESPONSE=$(HOME="$HOME_A" timeout 30 opencode "$PROMPT" 2>/dev/null \
    || echo "(opencode requires TTY — falling back to direct Ollama API)")
  echo "  Response: $RESPONSE"
else
  # Direct Ollama API call — same model the opencode.json points to
  if [[ "$OLLAMA_OK" == "true" ]]; then
    ok "Using Ollama API directly (opencode requires TTY)"
    RESPONSE=$(curl -sf "$OLLAMA_URL/api/generate" \
      --max-time 30 \
      -d "{\"model\":\"$OLLAMA_MODEL\",\"prompt\":\"$PROMPT\",\"stream\":false}" \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('response','').strip())" 2>/dev/null \
      || echo "(no response)")
    ok "Ollama responded: $RESPONSE"
  else
    RESPONSE="A symlink is a file that points to another file or directory."
    warn "Simulated response (Ollama unreachable)"
  fi
fi

# A-4: create realistic OpenCode session data in the data dir
mkdir -p "$HOME_A/.local/share/opencode/sessions"
cat > "$HOME_A/.local/share/opencode/sessions/${SESSION_ID}.json" << EOF
{
  "id": "$SESSION_ID",
  "model": "ollama/$OLLAMA_MODEL",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "messages": [
    {"role": "user",    "content": "$PROMPT"},
    {"role": "assistant","content": "$RESPONSE"}
  ]
}
EOF
ok "Session created: ~/.local/share/opencode/sessions/${SESSION_ID}.json"

# ── GAP-2: backup claude fails — no data field ────────────────────────────────
section "GAP-2 check: backup claude"
BACKUP_CLAUDE_OUT=$(HOME="$HOME_A" "$BIN_A" backup claude 2>&1 || true)
if echo "$BACKUP_CLAUDE_OUT" | grep -qi "no separate data"; then
  gap 2 "backup claude — Claude tool has no 'data' field in nx-agents.toml
     Claude's runtime data lives in store/claude/ (already symlinked from ~/.claude).
     Running 'backup claude' fails: \"$(echo "$BACKUP_CLAUDE_OUT" | head -1 | xargs)\"
     ROOT CAUSE : nx-agents.toml claude[[tool]] missing: data = \"~/.claude\"
     CODE       : nx-agents.toml:37-54
     FIX        : Add data = \"~/.claude\" to the claude tool entry."
else
  ok "backup claude: $BACKUP_CLAUDE_OUT"
fi

# A-5: backup opencode (has a data field — this should work)
section "Backup opencode"
if HOME="$HOME_A" "$BIN_A" backup opencode 2>&1 | grep -E '(✓|Backup)' | head -5; then
  OC_BAK=$(ls -d "$HOME_A"/.opencode.bak.* 2>/dev/null | tail -1 || echo "")
  [[ -n "$OC_BAK" ]] && ok "opencode backup at: $OC_BAK"
else
  warn "backup opencode had no output — check data dir exists"
fi

# A-6: commit everything to store/ and sync to remote
section "Sync store/ to remote"
git -C "$NX_A/store" add -A 2>/dev/null
git -C "$NX_A/store" commit -q -m "Machine A: opencode config + session" --allow-empty
BRANCH=$(git -C "$NX_A/store" symbolic-ref --short HEAD 2>/dev/null || echo "master")
git -C "$NX_A/store" push -u origin "$BRANCH" -q
ok "Pushed to remote (branch: $BRANCH)"
ok "Remote contains: $(git -C "$NX_A/store" ls-tree --name-only HEAD | tr '\n' '  ')"

# ── PHASE B: Machine B — fresh device, attempt restore ───────────────────────
section "PHASE B: Machine B (new device — restore attempt)"
install_nx "$HOME_B" "$NX_B" "$BIN_B"

# B-1: run setup with the same remote URL
ok "Running setup with remote URL: $REMOTE_STORE"
printf 'y\n%s\n' "$REMOTE_STORE" | HOME="$HOME_B" "$BIN_B" setup 2>&1 \
  | grep -E '(✓|->|!)' | head -20 || true

# ── GAP-1: setup doesn't clone from existing remote ──────────────────────────
section "GAP-1 check: is store data present on Machine B?"
OC_CONF_B="$HOME_B/.config/opencode/opencode.json"
if [[ -f "$OC_CONF_B" ]]; then
  ok "opencode.json present — restore succeeded (unexpected!)"
else
  gap 1 "setup with remote URL does NOT clone existing store data.
     Remote has commits (branch: $BRANCH, HEAD: $(git ls-remote "$REMOTE_STORE" HEAD | cut -c1-8)).
     Machine B store/opencode/ is empty: $(ls "$NX_B/store/opencode/" 2>/dev/null | tr '\n' ' ' || echo '(empty)')
     ~/.config/opencode/opencode.json: MISSING
     ROOT CAUSE : setup.sh:19-37 runs 'git init + git remote add' but never fetches.
     CODE       : src/commands/setup.sh lines 19-37
     FIX        : After 'git remote add', call 'git ls-remote origin HEAD'.
                  If remote has commits → prompt 'Restore from remote? [Y/n]'
                  If yes → 'git fetch origin && git checkout -b \$BRANCH origin/\$BRANCH'"
fi

# ── GAP-3: no atomic restore command ─────────────────────────────────────────
HELP_OUT=$(HOME="$HOME_B" "$BIN_B" --help 2>&1 || true)
if ! echo "$HELP_OUT" | grep -q "restore\b"; then
  gap 3 "No 'restore <remote>' command exists.
     'restoreFromBkp' only restores from a local ~/.tool.bak.* directory.
     There is no single command to clone a remote store and wire all symlinks
     on a new device — currently requires two manual steps:
       1. git clone <remote> ~/.nx-agents-config/store
       2. nx-agents-config setup
     ROOT CAUSE : src/commands/ has no cross-device restore command.
     FIX        : Add 'restore <remote>' command:
                  git clone <remote> store/ → run setup symlink logic."
fi

# ── Verify the manual workaround ─────────────────────────────────────────────
section "Manual workaround: git clone store + re-setup"
rm -rf "$NX_B/store"
git clone "$REMOTE_STORE" "$NX_B/store" -q
ok "Cloned remote to Machine B store/"
printf 'n\n' | HOME="$HOME_B" "$BIN_B" setup 2>&1 \
  | grep -E '(✓|->|!)' | head -20 || true

if [[ -f "$OC_CONF_B" ]]; then
  ok "opencode.json present after manual workaround"
  ok "Configured model: $(python3 -c "import json; d=json.load(open('$OC_CONF_B')); print(d.get('model','?'))")"
  ok "Manual workaround WORKS — but requires 2 steps instead of 1"
else
  warn "opencode.json still missing after manual workaround — investigate symlinks"
fi

# Session was not in store/ (it lives in ~/.local/share/opencode, backed up separately)
if ls "$HOME_B/.local/share/opencode/sessions/" 2>/dev/null | grep -q .; then
  ok "Sessions restored"
else
  warn "Sessions NOT restored — those live in ~/.local/share/opencode/ (data dir, not store/)"
  warn "Need: 'backup opencode' on Machine A + copy backup to Machine B"
fi

# ── Gap summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${B}══════════════════════════════════════════════════════════${NC}"
echo -e "${B}  Gap Test Complete — ${#GAPS[@]} gap(s) identified${NC}"
echo -e "${B}══════════════════════════════════════════════════════════${NC}"
echo ""
for id in "${GAPS[@]}"; do
  case "$id" in
    1) echo -e "  ${R}GAP-1${NC}  setup doesn't clone from existing remote"
       echo -e "         fix: src/commands/setup.sh — add git ls-remote + fetch/checkout";;
    2) echo -e "  ${R}GAP-2${NC}  backup claude fails — no 'data' field in nx-agents.toml"
       echo -e "         fix: nx-agents.toml — add data = \"~/.claude\" to claude tool";;
    3) echo -e "  ${R}GAP-3${NC}  no single-command cross-device restore"
       echo -e "         fix: new src/commands/restore.sh + dispatch in main.sh";;
  esac
done
echo ""
echo -e "  See ${C}spec/restore-gap.md${NC} for the full implementation spec."
