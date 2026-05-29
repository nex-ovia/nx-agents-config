#!/usr/bin/env bash
# lifecycle-machine-b.sh — Stage 4: restore and verify session resumption
# Runs inside Dockerfile.restore container. HOME=/tmp/machine-b-home
set -euo pipefail

HOME=/tmp/machine-b-home
NX_HOME="$HOME/.nx-agents-config"
BARE_REPO="${BARE_REPO:-/tmp/store-remote.git}"
PASS=0; FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); exit 1; }
assert_eq()  { [[ "$1" == "$2" ]] || fail "Expected '$2', got '$1': $3"; }
assert_dir() { [[ -d "$1" ]] || fail "Expected directory: $1"; }
assert_file(){ [[ -f "$1" ]] || fail "Expected file: $1"; }
assert_link(){ [[ -L "$1" ]] || fail "Expected symlink: $1"; }
assert_contains() { echo "$1" | grep -q "$2" || fail "Expected '$2' in: $1"; }

echo "══════════════════════════════════════════════"
echo "  Machine B — Stage 4 (restore + verify)"
echo "  HOME: $HOME"
echo "  Bare remote: $BARE_REPO"
echo "══════════════════════════════════════════════"

# ── Stage 4: Restore and verify ────────────────────────────────────────────

echo ""
echo "── Stage 4: Restore from remote ───────────────────────────────────────"

# Restore (answer 'n' to git-init prompt inside cmd_setup — store already cloned)
printf 'n\n' | HOME="$HOME" nx-agents-config restore "$BARE_REPO"

assert_dir "$NX_HOME/store/.git"
pass "Stage 4: store/ cloned with .git"

assert_link "$HOME/.config/opencode"
pass "Stage 4: ~/.config/opencode symlink wired"

assert_link "$HOME/.local/share/opencode"
pass "Stage 4: ~/.local/share/opencode symlink wired"

echo ""
echo "── Stage 4: Verify session data ───────────────────────────────────────"

DB="$NX_HOME/store/opencode/userdata/opencode.db"
assert_file "$DB"
pass "Stage 4: opencode.db present"

SESSION_IDS=$(sqlite3 "$DB" "SELECT id FROM session;" 2>/dev/null || echo "")
assert_contains "$SESSION_IDS" "test-session-001"
pass "Stage 4: test-session-001 present in restored opencode.db"

echo ""
echo "── Stage 4: Verify config ─────────────────────────────────────────────"

CONFIG=$(cat "$HOME/.config/opencode/opencode.json" 2>/dev/null || echo "")
assert_contains "$CONFIG" "tinyllama"
pass "Stage 4: opencode.json contains tinyllama"
assert_contains "$CONFIG" "localhost:11434"
pass "Stage 4: opencode.json contains localhost:11434"

echo ""
echo "══════════════════════════════════════════════"
echo "  Machine B results: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════════════"
[[ $FAIL -eq 0 ]]
