#!/usr/bin/env bash
# suite.sh — Integration tests for nx-agents-config (runs inside Docker container)
# All tests run against a synthetic $HOME so the host machine is never touched.
set -euo pipefail

REPO="/repo"
TESTHOME="/tmp/testhome"
NX_HOME="$TESTHOME/.nx-agents-config"
BIN="$NX_HOME/nx-agents-config"

PASS=0
FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────────

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }

fail() {
  echo "FAIL: $1"
  FAIL=$((FAIL + 1))
  exit 1
}

# Run a command, capture output; print it and fail if non-zero exit.
t() {
  local desc="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    pass "$desc"
  else
    echo "--- output ---"
    echo "$out"
    fail "$desc"
  fi
}

# Run command with HOME overridden
th() {
  local desc="$1"; shift
  local out
  if out=$(HOME="$TESTHOME" "$@" 2>&1); then
    pass "$desc"
  else
    echo "--- output ---"
    echo "$out"
    fail "$desc"
  fi
}

assert_dir()     { [[ -d "$1" ]] || fail "Expected directory: $1"; }
assert_symlink() { [[ -L "$1" ]] || fail "Expected symlink: $1"; }
assert_file()    { [[ -f "$1" ]] || fail "Expected file: $1"; }
assert_no_path() { [[ ! -e "$1" ]] || fail "Expected path absent: $1"; }

# ── reset fake home ───────────────────────────────────────────────────────────

reset_home() {
  rm -rf "$TESTHOME"
  mkdir -p "$TESTHOME/.local/bin"
  mkdir -p "$NX_HOME"
  cp /tmp/nx-agents-config-bin "$BIN"
  chmod +x "$BIN"
}

# ── T01: dev mode entrypoint sources correctly ───────────────────────────────
echo ""
echo "── T01: dev mode --help ────────────────────────────────────────────────"
t "T01: dev mode --help" bash -c "cd $REPO && bin/nx-agents-config --help"

# ── T02: build produces a working binary ─────────────────────────────────────
echo ""
echo "── T02: build ──────────────────────────────────────────────────────────"
t "T02: bash build.sh" bash -c "cd $REPO && bash build.sh /tmp/nx-agents-config-bin"
[[ -x "/tmp/nx-agents-config-bin" ]] || fail "T02: binary not executable"
t "T02: built binary --help" bash -c "HOME=$TESTHOME /tmp/nx-agents-config-bin --help"

# Install binary into fake home
rm -rf "$TESTHOME"
mkdir -p "$TESTHOME/.local/bin" "$NX_HOME"
cp /tmp/nx-agents-config-bin "$BIN"
chmod +x "$BIN"

# ── T03: tree renders before setup ───────────────────────────────────────────
echo ""
echo "── T03: tree (pre-setup) ───────────────────────────────────────────────"
th "T03: tree (pre-setup)" "$BIN" tree

# ── T04: --dry-run setup leaves no store/ ────────────────────────────────────
echo ""
echo "── T04: --dry-run setup ────────────────────────────────────────────────"
th "T04: --dry-run setup" "$BIN" --dry-run setup
assert_no_path "$NX_HOME/store"
pass "T04: --dry-run left no store/"

# ── T05: real setup (skip git init) ──────────────────────────────────────────
echo ""
echo "── T05: setup (no git) ─────────────────────────────────────────────────"
out=$(echo 'n' | HOME="$TESTHOME" "$BIN" setup 2>&1) || { echo "$out"; fail "T05: setup failed"; }
pass "T05: setup exited 0"
assert_dir "$NX_HOME/store"
pass "T05: store/ created"
assert_dir "$NX_HOME/store/claude"
pass "T05: store/claude created"
assert_dir "$NX_HOME/store/opencode"
pass "T05: store/opencode created"
assert_dir "$NX_HOME/shared/skills"
pass "T05: shared/skills created"
assert_symlink "$TESTHOME/.claude"
pass "T05: ~/.claude symlink created"
assert_symlink "$TESTHOME/.config/opencode"
pass "T05: ~/.config/opencode symlink created"
assert_symlink "$TESTHOME/.local/share/opencode"
pass "T05: ~/.local/share/opencode symlink created"
assert_dir "$NX_HOME/store/opencode/userdata"
pass "T05: store/opencode/userdata/ created"
assert_file "$NX_HOME/store/opencode/userdata/.gitignore"
pass "T05: store/opencode/userdata/.gitignore created"
assert_symlink "$TESTHOME/.local/bin/nx-agents-config"
pass "T05: CLI symlink created"

# ── T06: tree post-setup shows tool names ────────────────────────────────────
echo ""
echo "── T06: tree post-setup ────────────────────────────────────────────────"
OUT=$(HOME="$TESTHOME" "$BIN" tree 2>&1) || fail "T06: tree failed"
echo "$OUT" | grep -q "claude"   || fail "T06: 'claude' missing from tree"
echo "$OUT" | grep -q "opencode" || fail "T06: 'opencode' missing from tree"
pass "T06: tree shows claude and opencode"

# ── T07: update is idempotent on clean state ─────────────────────────────────
echo ""
echo "── T07: update (idempotent) ────────────────────────────────────────────"
th "T07: update idempotent" "$BIN" update
# Verify no .removed.* dirs created when nothing is orphaned
REMOVED_DIRS=()
for _d in "$NX_HOME"/.removed.*/; do [[ -d "$_d" ]] && REMOVED_DIRS+=("$_d"); done
[[ "${#REMOVED_DIRS[@]}" -eq 0 ]] || fail "T07: unexpected .removed.* dirs on clean state"
pass "T07: no orphans on clean state"

# ── T08: orphan detection moves unknown dirs ──────────────────────────────────
echo ""
echo "── T08: orphan detection ───────────────────────────────────────────────"
mkdir -p "$NX_HOME/store/ghost-tool"
out=$(HOME="$TESTHOME" "$BIN" update 2>&1) || { echo "$out"; fail "T08: update with orphan failed"; }
pass "T08: update with orphan exited 0"
assert_no_path "$NX_HOME/store/ghost-tool"
pass "T08: orphan removed from store/"
REMOVED=$(ls -d "$NX_HOME"/.removed.* 2>/dev/null | head -1 || true)
[[ -n "$REMOVED" ]] || fail "T08: no .removed.* dir created"
[[ -d "$REMOVED/ghost-tool" ]] || fail "T08: ghost-tool not in .removed.*/"
pass "T08: ghost-tool moved to .removed.*/"

# ── T09: backup opencode (seed fake data dir) ────────────────────────────────
echo ""
echo "── T09: backup opencode ────────────────────────────────────────────────"
FAKE_OC_DATA="$TESTHOME/.local/share/opencode"
mkdir -p "$FAKE_OC_DATA/sessions"
echo '{"id":"s1"}' > "$FAKE_OC_DATA/sessions/s1.json"
th "T09: backup opencode" "$BIN" backup opencode
OC_BAK=$(ls -d "$TESTHOME"/.opencode.bak.* 2>/dev/null | head -1 || true)
[[ -n "$OC_BAK" ]] || fail "T09: no .opencode.bak.* created"
assert_file "$OC_BAK/sessions/s1.json"
pass "T09: backup contents verified"

# ── T10: restoreFromBkp opencode ─────────────────────────────────────────────
echo ""
echo "── T10: restoreFromBkp opencode ────────────────────────────────────────"
rm -rf "$FAKE_OC_DATA"
# Prompts: "Create it? [Y/n]" then "Continue? [y/N]"
out=$(printf 'y\ny\n' | HOME="$TESTHOME" "$BIN" restoreFromBkp opencode 2>&1) \
  || { echo "$out"; fail "T10: restoreFromBkp failed"; }
pass "T10: restoreFromBkp exited 0"
assert_dir "$FAKE_OC_DATA"
pass "T10: data dir restored"
assert_file "$FAKE_OC_DATA/sessions/s1.json"
pass "T10: session file restored"

# ── T11: sync with local bare repo as remote ─────────────────────────────────
echo ""
echo "── T11: sync (git) ─────────────────────────────────────────────────────"
BARE_REPO="/tmp/store-remote.git"
rm -rf "$BARE_REPO"
git init --bare "$BARE_REPO" -q
git -C "$NX_HOME/store" init -q
git -C "$NX_HOME/store" remote add origin "$BARE_REPO"
git -C "$NX_HOME/store" add -A
git -C "$NX_HOME/store" commit -q -m "initial" --allow-empty
BRANCH=$(git -C "$NX_HOME/store" symbolic-ref --short HEAD 2>/dev/null || echo "master")
git -C "$NX_HOME/store" push -u origin "$BRANCH" -q
# Working tree is clean and upstream is current → no interactive prompts
th "T11: sync (clean state)" "$BIN" sync

# ── T12: project add + list ───────────────────────────────────────────────────
echo ""
echo "── T12: project add + list ─────────────────────────────────────────────"
th "T12: project add test-proj" "$BIN" project add test-proj
assert_dir "$NX_HOME/store/shared/projects/test-proj"
pass "T12: project dir created"
assert_file "$NX_HOME/store/shared/projects/test-proj/meta.toml"
pass "T12: meta.toml created"
assert_file "$NX_HOME/store/shared/projects/test-proj/context.md"
pass "T12: context.md created"
assert_file "$NX_HOME/store/shared/projects/test-proj/sessions.toml"
pass "T12: sessions.toml created"
OUT=$(HOME="$TESTHOME" "$BIN" project list 2>&1) || fail "T12: project list failed"
echo "$OUT" | grep -q "test-proj" || fail "T12: test-proj not in project list"
pass "T12: project list shows test-proj"

# ── T13: uninstall backs up store and removes symlinks ───────────────────────
echo ""
echo "── T13: uninstall ──────────────────────────────────────────────────────"
out=$(echo 'y' | HOME="$TESTHOME" "$BIN" uninstall 2>&1) \
  || { echo "$out"; fail "T13: uninstall failed"; }
pass "T13: uninstall exited 0"
# Store backup should exist in TESTHOME
STORE_BAK=$(ls -d "$TESTHOME"/.nx-agents-config.store.bak.* 2>/dev/null | head -1 || true)
[[ -n "$STORE_BAK" ]] || fail "T13: no store backup created"
pass "T13: store backup created at $STORE_BAK"
# External tool symlinks should be removed
assert_no_path "$TESTHOME/.claude"
pass "T13: ~/.claude symlink removed"
assert_no_path "$TESTHOME/.config/opencode"
pass "T13: ~/.config/opencode symlink removed"
# NX_AGENTS_HOME itself removed
assert_no_path "$NX_HOME"
pass "T13: NX_AGENTS_HOME removed"

# ── T14: --dry-run leaves filesystem unchanged ───────────────────────────────
echo ""
echo "── T14: --dry-run setup ────────────────────────────────────────────────"
reset_home
out=$(HOME="$TESTHOME" "$BIN" --dry-run setup 2>&1) || { echo "$out"; fail "T14: --dry-run setup failed"; }
pass "T14: --dry-run setup exited 0"
assert_no_path "$NX_HOME/store"
pass "T14: no store/ created by --dry-run"
assert_no_path "$TESTHOME/.claude"
pass "T14: no ~/.claude symlink created by --dry-run"

# ── T15: restore <remote> clones store and wires symlinks ────────────────────
echo ""
echo "── T15: restore <remote> ───────────────────────────────────────────────"
reset_home
BARE_REPO2="/tmp/store-remote2.git"
rm -rf "$BARE_REPO2" /tmp/restore-seed
git init --bare "$BARE_REPO2" -q
mkdir -p /tmp/restore-seed
git -C /tmp/restore-seed init -q
echo "test" > /tmp/restore-seed/test.txt
git -C /tmp/restore-seed add -A
git -C /tmp/restore-seed commit -q -m "seed" --allow-empty
BRANCH2=$(git -C /tmp/restore-seed symbolic-ref --short HEAD 2>/dev/null || echo "master")
git -C /tmp/restore-seed remote add origin "$BARE_REPO2"
git -C /tmp/restore-seed push -u origin "$BRANCH2" -q
out=$(printf 'n\n' | HOME="$TESTHOME" "$BIN" restore "$BARE_REPO2" 2>&1) \
  || { echo "$out"; fail "T15: restore failed"; }
pass "T15: restore exited 0"
assert_dir "$NX_HOME/store/.git"
pass "T15: store/.git cloned"
assert_symlink "$TESTHOME/.claude"
pass "T15: ~/.claude symlink wired after restore"
assert_symlink "$TESTHOME/.config/opencode"
pass "T15: ~/.config/opencode symlink wired after restore"

# ── T16: backup claude succeeds (data = ~/.claude) ────────────────────────────
echo ""
echo "── T16: backup claude ──────────────────────────────────────────────────"
reset_home
out=$(printf 'n\n' | HOME="$TESTHOME" "$BIN" setup 2>&1) \
  || { echo "$out"; fail "T16: setup failed"; }
# Seed data via the ~/.claude symlink (which points to store/claude/)
mkdir -p "$TESTHOME/.claude/sessions"
echo '{"id":"c1"}' > "$TESTHOME/.claude/sessions/c1.jsonl"
th "T16: backup claude" "$BIN" backup claude
CLAUDE_BAK=$(ls -d "$TESTHOME"/.claude.bak.* 2>/dev/null | head -1 || true)
[[ -n "$CLAUDE_BAK" ]] || fail "T16: no .claude.bak.* created"
assert_file "$CLAUDE_BAK/sessions/c1.jsonl"
pass "T16: backup claude contents verified"

# ── T17: auto-sync commits and pushes without interactive prompts ─────────────
echo ""
echo "── T17: auto-sync (no prompts) ─────────────────────────────────────────"
reset_home
out=$(printf 'n\n' | HOME="$TESTHOME" "$BIN" setup 2>&1) \
  || { echo "$out"; fail "T17: setup failed"; }
BARE_REPO3="/tmp/store-remote3.git"
rm -rf "$BARE_REPO3"
git init --bare "$BARE_REPO3" -q
git -C "$NX_HOME/store" init -q
git -C "$NX_HOME/store" remote add origin "$BARE_REPO3"
git -C "$NX_HOME/store" add -A
git -C "$NX_HOME/store" commit -q -m "initial" --allow-empty
BRANCH3=$(git -C "$NX_HOME/store" symbolic-ref --short HEAD 2>/dev/null || echo "master")
git -C "$NX_HOME/store" push -u origin "$BRANCH3" -q
echo "new-data" > "$NX_HOME/store/claude/test.txt"
out=$(HOME="$TESTHOME" "$BIN" sync "T17 auto-sync test" 2>&1) \
  || { echo "$out"; fail "T17: sync failed"; }
pass "T17: auto-sync exited 0"
REMOTE_LOG=$(git -C "$BARE_REPO3" log --oneline 2>/dev/null || true)
echo "$REMOTE_LOG" | grep -q "T17 auto-sync test" || fail "T17: custom message not on remote"
pass "T17: commit with custom message pushed to remote"

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════════════"
[[ $FAIL -eq 0 ]]
