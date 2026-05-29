#!/usr/bin/env bash
# lifecycle-machine-a.sh — Stages 1-3: install, session, backup, sync
# Runs inside Dockerfile.opencode container. HOME=/tmp/machine-a-home
set -euo pipefail

HOME=/tmp/machine-a-home
NX_HOME="$HOME/.nx-agents-config"
BARE_REPO="${BARE_REPO:-/tmp/store-remote.git}"
PASS=0; FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); exit 1; }
assert_eq()  { [[ "$1" == "$2" ]] || fail "Expected '$2', got '$1': $3"; }
assert_dir() { [[ -d "$1" ]] || fail "Expected directory: $1"; }
assert_file(){ [[ -f "$1" ]] || fail "Expected file: $1"; }
assert_link(){ [[ -L "$1" ]] || fail "Expected symlink: $1"; }

echo "══════════════════════════════════════════════"
echo "  Machine A — Stages 1–3"
echo "  HOME: $HOME"
echo "  Bare remote: $BARE_REPO"
echo "══════════════════════════════════════════════"

# ── Stage 1: Start LLM and create live session ─────────────────────────────

echo ""
echo "── Stage 1: LLM + live session ────────────────────────────────────────"

# Start ollama (background)
ollama serve &>/tmp/ollama.log &
OLLAMA_PID=$!
sleep 4

# Verify model ready
TAGS=$(curl -sf http://localhost:11434/api/tags 2>/dev/null || echo "")
echo "$TAGS" | grep -q "tinyllama" || fail "Stage 1: tinyllama not in ollama model list"
pass "Stage 1: local Ollama running with tinyllama"

# Write opencode.json
mkdir -p "$HOME/.config/opencode"
cat > "$HOME/.config/opencode/opencode.json" << 'EOF'
{
  "model": "ollama/tinyllama",
  "provider": { "ollama": { "url": "http://localhost:11434" } }
}
EOF
python3 -c "import json; json.load(open('$HOME/.config/opencode/opencode.json'))"
pass "Stage 1: opencode.json written and valid JSON"

# Run a real prompt
RESPONSE=$(curl -sf -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"tinyllama","prompt":"In one sentence: what is a symlink?","stream":false}' \
  2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('response',''))" || echo "")
[[ -n "$RESPONSE" ]] || fail "Stage 1: empty response from Ollama"
pass "Stage 1: Ollama prompt returned non-empty response"

# Seed opencode.db with a session row
mkdir -p "$HOME/.local/share/opencode"
sqlite3 "$HOME/.local/share/opencode/opencode.db" << 'EOF'
CREATE TABLE IF NOT EXISTS session (id TEXT PRIMARY KEY, title TEXT, created INTEGER);
INSERT OR IGNORE INTO session VALUES ('test-session-001', 'symlink explanation', strftime('%s','now'));
EOF
COUNT=$(sqlite3 "$HOME/.local/share/opencode/opencode.db" "SELECT COUNT(*) FROM session;")
assert_eq "$COUNT" "1" "session row count"
pass "Stage 1: session row seeded in opencode.db"

# ── Stage 2: Install nx-agents-config and wire symlinks ───────────────────

echo ""
echo "── Stage 2: Setup and wire symlinks ───────────────────────────────────"

# setup: skip git init (n), no remote
printf 'n\n' | HOME="$HOME" nx-agents-config setup
assert_link "$HOME/.config/opencode"
pass "Stage 2: ~/.config/opencode is a symlink"
assert_link "$HOME/.local/share/opencode"
pass "Stage 2: ~/.local/share/opencode is a symlink"
assert_dir "$NX_HOME/store/opencode/userdata"
pass "Stage 2: store/opencode/userdata/ exists"
assert_file "$NX_HOME/store/opencode/userdata/.gitignore"
pass "Stage 2: store/opencode/userdata/.gitignore exists"

# Verify session survived the wire-up
COUNT=$(sqlite3 "$NX_HOME/store/opencode/userdata/opencode.db" "SELECT COUNT(*) FROM session;")
assert_eq "$COUNT" "1" "session count in store after setup"
pass "Stage 2: session row present in store/opencode/userdata/opencode.db"

# ── Stage 3: Backup and sync ──────────────────────────────────────────────

echo ""
echo "── Stage 3: Backup and sync ────────────────────────────────────────────"

HOME="$HOME" nx-agents-config backup opencode
OC_BAK=$(ls -d "$HOME"/.opencode.bak.* 2>/dev/null | head -1 || true)
[[ -n "$OC_BAK" ]] || fail "Stage 3: no .opencode.bak.* created"
COUNT=$(sqlite3 "$OC_BAK/opencode.db" "SELECT COUNT(*) FROM session;" 2>/dev/null || echo "0")
assert_eq "$COUNT" "1" "session count in backup"
pass "Stage 3: backup opencode — DB with session row"

# Init git, push to bare remote
git -C "$NX_HOME/store" init -q
git -C "$NX_HOME/store" remote add origin "$BARE_REPO"
git -C "$NX_HOME/store" add -A
git -C "$NX_HOME/store" commit -q -m "Machine A: opencode session + config"
BRANCH=$(git -C "$NX_HOME/store" symbolic-ref --short HEAD 2>/dev/null || echo "master")
git -C "$NX_HOME/store" push -u origin "$BRANCH" -q

REMOTE_SHA=$(git ls-remote "$BARE_REPO" HEAD 2>/dev/null | cut -f1 || echo "")
[[ -n "$REMOTE_SHA" ]] || fail "Stage 3: bare remote has no HEAD after push"
pass "Stage 3: store pushed to bare remote (SHA: ${REMOTE_SHA:0:8})"

# Auto-sync (no prompts)
HOME="$HOME" nx-agents-config sync "after session 001"
pass "Stage 3: sync exited 0"

kill "$OLLAMA_PID" 2>/dev/null || true

echo ""
echo "══════════════════════════════════════════════"
echo "  Machine A results: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════════════"
[[ $FAIL -eq 0 ]]
