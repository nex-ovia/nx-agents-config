#!/usr/bin/env bash
# run-lifecycle.sh — Build images, run OpenCode lifecycle stages, print report.
# Requires: docker, test/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BARE_REPO=/tmp/store-remote.git

# ── Preflight ────────────────────────────────────────────────────────────────

if [[ ! -f "$REPO_ROOT/test/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf" ]]; then
  echo "[err] GGUF model not found. Download it first:"
  echo "      mkdir -p test/models"
  echo "      # From: https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF"
  echo "      curl -L -o test/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf <url>"
  exit 1
fi

# ── Build binary ─────────────────────────────────────────────────────────────

echo ""
echo "==> Building nx-agents-config binary"
bash "$REPO_ROOT/build.sh"

# ── Shared bare remote (mounted into both containers) ────────────────────────

echo ""
echo "==> Preparing shared bare remote at $BARE_REPO"
rm -rf "$BARE_REPO"
git init --bare "$BARE_REPO" -q

# ── Machine A: install, session, backup, sync ─────────────────────────────────

echo ""
echo "==> Building Machine A image (OpenCode + ollama + GGUF)"
docker build \
  -f "$REPO_ROOT/test/Dockerfile.opencode" \
  -t nx-agents-opencode-test \
  "$REPO_ROOT"

echo ""
echo "==> Running Machine A (Stages 1–3)"
docker run --rm \
  -v "$BARE_REPO:$BARE_REPO" \
  -e BARE_REPO="$BARE_REPO" \
  nx-agents-opencode-test

# ── Machine B: restore and verify ────────────────────────────────────────────

echo ""
echo "==> Building Machine B image (restore only)"
docker build \
  -f "$REPO_ROOT/test/Dockerfile.restore" \
  -t nx-agents-restore-test \
  "$REPO_ROOT"

echo ""
echo "==> Running Machine B (Stage 4)"
docker run --rm \
  -v "$BARE_REPO:$BARE_REPO" \
  -e BARE_REPO="$BARE_REPO" \
  nx-agents-restore-test

# ── Report ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════"
echo "  OpenCode Lifecycle — ALL STAGES PASSED"
echo "══════════════════════════════════════════════"
echo ""
echo "| Stage | Test | Result |"
echo "|-------|------|--------|"
echo "| Install | OpenCode + nx-agents-config setup | ✓ |"
echo "| LLM | Local GGUF model (tinyllama) ready | ✓ |"
echo "| Session | Prompt via local Ollama (tinyllama) | ✓ |"
echo "| Session | Row in opencode.db | ✓ |"
echo "| Backup | nx-agents-config backup opencode | ✓ |"
echo "| Sync | nx-agents-config sync → bare remote | ✓ |"
echo "| Restore | nx-agents-config restore on Machine B | ✓ |"
echo "| Verify | opencode.db present with session row | ✓ |"
echo "| Verify | ~/.config/opencode/opencode.json correct | ✓ |"
echo "| Verify | ~/.local/share/opencode → store/opencode/userdata/ | ✓ |"
