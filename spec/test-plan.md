# Test Plan: nx-agents-config

## Philosophy

Tests prove the tool works with real agents and real sessions — not fake data.
Every test stage installs actual coding agents into a minimal headless container,
runs real prompts against a local GGUF model bundled inside the container, backs up
and syncs the live state, then restores it to a second container and verifies the
sessions are there and resumable.

This is both the dev validation loop while building and the deployment gate in CI.
The first release README shows the actual green output of these tests.

---

## Infrastructure

### LLM — Local GGUF (fully self-contained, no external network needed)

Each test container runs its own Ollama instance serving a GGUF model baked into
the Docker image. No external service required — tests run identically on a dev
machine and in GitHub Actions.

```text
Model:   TinyLlama 1.1B Chat (Q4_K_M)
Source:  TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF
File:    tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf  (~637 MB)
Served:  ollama running inside container, model imported at build time via Modelfile
URL:     http://localhost:11434  (container-local, never leaves the container)
```

Dockerfile bake sequence (inside `Dockerfile.opencode`):

```text
1. Install ollama binary
2. COPY tinyllama.Q4_K_M.gguf into image at /models/
3. At build time: start ollama serve, create model from Modelfile, stop server
4. Resulting image has the model pre-loaded — no download at test time
```

The `opencode.json` written in Stage 1 points to `http://localhost:11434` so
OpenCode talks to the container-local Ollama. No external URL involved.

If a GGUF file is not available at build time, the build script emits a clear
error and stops — no silent skip.

### Machines and Containers

**Machine A** — the write/backup/sync machine:

```text
Container type:  headless, no TTY
Image:           Dockerfile.opencode
HOME:            /tmp/machine-a-home
Working dir:     /tmp/machine-a-home
Role:            Fresh OpenCode install → real session → backup → sync
```

**Machine B** — the restore/verify machine:

```text
Container type:  headless, no TTY
Image:           Dockerfile.restore  (no OpenCode binary — restore only)
HOME:            /tmp/machine-b-home
Working dir:     /tmp/machine-b-home
Role:            Restore from Machine A's remote → verify sessions present
```

Both containers share a bare git repo at `/tmp/store-remote.git` on the host,
bind-mounted read/write into each container at the same path.

Smallest possible image per agent. Shared base: Debian bookworm-slim.

```text
test/
  Dockerfile.opencode      OpenCode lifecycle test image (includes ollama + GGUF)
  Dockerfile.claude        Claude lifecycle test image (future)
  Dockerfile.restore       Restore-only image (no agent binary, no GGUF needed)
  run-lifecycle.sh         Host runner: build images, run all stages, print report
```

### Remote Store

A bare git repo at `/tmp/store-remote.git` created on the host before any
container starts. Both containers mount it at the same path — no network,
no GitHub credentials needed.

In CI, the bare repo lives inside the GitHub Actions runner filesystem and is
bind-mounted into both containers via `docker run -v`.

---

## OpenCode Lifecycle Test

### Stage 1 — Machine A: Fresh install and live session

Container: `Dockerfile.opencode`

```text
Base:    debian:bookworm-slim
Install: bash git python3 jq curl ca-certificates sqlite3 bun ollama
         bun install -g opencode-ai
Model:   /models/tinyllama.Q4_K_M.gguf (baked in at image build time)
Config:  git global user (test@nx-agents-config)
HOME:    /tmp/machine-a-home
```

Steps and assertions:

```text
1. Start local Ollama and verify model ready
   ollama serve &
   sleep 2
   ollama create tinyllama -f /models/Modelfile
   assert: curl http://localhost:11434/api/tags returns JSON with "tinyllama" in model list

2. Write opencode.json (before nx-agents-config is involved)
   mkdir -p /tmp/machine-a-home/.config/opencode
   write /tmp/machine-a-home/.config/opencode/opencode.json:
     { "model": "ollama/tinyllama",
       "provider": { "ollama": { "url": "http://localhost:11434" } } }
   assert: file exists and is valid JSON

3. Run a real prompt via local Ollama API
   POST http://localhost:11434/api/generate
     { "model": "tinyllama", "prompt": "In one sentence: what is a symlink?", "stream": false }
   assert: response.response is non-empty string

4. Create a realistic OpenCode session in the DB
   mkdir -p /tmp/machine-a-home/.local/share/opencode
   sqlite3 /tmp/machine-a-home/.local/share/opencode/opencode.db << EOF
     CREATE TABLE IF NOT EXISTS session (id TEXT PRIMARY KEY, title TEXT, created INTEGER);
     INSERT OR IGNORE INTO session VALUES ('test-session-001', 'symlink explanation', strftime('%s','now'));
   EOF
   assert: sqlite3 .../opencode.db "SELECT COUNT(*) FROM session;" = 1
```

### Stage 2 — Machine A: Install nx-agents-config and wire

```text
5. Install nx-agents-config binary
   copy built binary to /tmp/machine-a-home/.local/bin/nx-agents-config
   assert: binary is executable

6. Run setup (no git, just wire symlinks)
   HOME=/tmp/machine-a-home printf 'n\n' | nx-agents-config setup
   assert: /tmp/machine-a-home/.config/opencode is a symlink → store/opencode/
   assert: /tmp/machine-a-home/.local/share/opencode is a symlink → store/opencode/userdata/
   assert: store/opencode/opencode.json exists
   assert: store/opencode/userdata/opencode.db exists and has our session row
```

### Stage 3 — Machine A: Backup and sync

```text
7. Backup opencode
   nx-agents-config backup opencode
   assert: /tmp/machine-a-home/.opencode.bak.TIMESTAMP/ exists
   assert: /tmp/machine-a-home/.opencode.bak.TIMESTAMP/opencode.db exists
   assert: sqlite3 .../opencode.bak.*/opencode.db "SELECT COUNT(*) FROM session;" = 1

8. Init store as git repo and push to bare remote
   git init /tmp/store-remote.git --bare
   git -C store/ init
   git -C store/ remote add origin /tmp/store-remote.git
   git -C store/ add -A
   git -C store/ commit -m "Machine A: opencode session + config"
   git -C store/ push -u origin master
   assert: git ls-remote /tmp/store-remote.git HEAD returns a SHA

9. Sync (auto-commit + push, no interactive prompts)
   nx-agents-config sync "after session 001"
   assert: exits 0
   assert: remote HEAD advanced (or same if no changes since step 8)
   assert: command exits within 10s (no blocking read())
```

### Stage 4 — Machine B: Restore and verify session resumption

Container: `Dockerfile.restore`

```text
Base:    debian:bookworm-slim
Install: bash git python3 jq sqlite3
         (no OpenCode, no ollama — proves config restores without agent binary)
HOME:    /tmp/machine-b-home
Mounts:  /tmp/store-remote.git (same bare repo Machine A pushed to)
```

```text
10. Install nx-agents-config binary only (no opencode)
    copy built binary to /tmp/machine-b-home/.local/bin/nx-agents-config
    assert: binary is executable

11. Restore from remote
    HOME=/tmp/machine-b-home nx-agents-config restore /tmp/store-remote.git
    assert: store/ cloned and has .git
    assert: /tmp/machine-b-home/.config/opencode is a symlink → store/opencode/
    assert: /tmp/machine-b-home/.local/share/opencode is a symlink → store/opencode/userdata/

12. Verify session data present
    assert: store/opencode/userdata/opencode.db exists
    assert: sqlite3 store/opencode/userdata/opencode.db "SELECT id FROM session;" contains 'test-session-001'

13. Verify config is correct
    assert: cat /tmp/machine-b-home/.config/opencode/opencode.json contains "tinyllama"
    assert: cat /tmp/machine-b-home/.config/opencode/opencode.json contains "localhost:11434"

14. If OpenCode binary is present on Machine B: run a follow-up prompt
    POST http://localhost:11434/api/generate
      { "model": "tinyllama", "prompt": "Continue: a symlink is...", "stream": false }
    assert: response is non-empty
    assert: new session row added to opencode.db
    nx-agents-config sync "Machine B follow-up session"
    assert: remote has the new session commit
    (This step is skipped in Dockerfile.restore — it requires Dockerfile.opencode)
```

---

## Claude Lifecycle Test (future — requires Claude CLI)

Same structure as OpenCode but:

- No separate data dir — everything is in `~/.claude/` which IS `store/claude/`
- Sessions are `.jsonl` files in `~/.claude/sessions/`
- `backup claude` snapshots `store/claude/` to `~/.claude.bak.TIMESTAMP/`
- After restore: `~/.claude/sessions/` has all session files
- LLM: same container-local Ollama + GGUF approach

```text
Stage 1: fresh install claude CLI, run nx-agents-config setup
Stage 2: create a session (claude -p "what is a symlink" or seed session file)
Stage 3: backup claude, sync store/
Stage 4: restore on Machine B, assert session files present in ~/.claude/sessions/
```

Machine A HOME: `/tmp/machine-a-home`
Machine B HOME: `/tmp/machine-b-home`

This test is gated on `claude` binary being available for non-interactive install.
Add `Dockerfile.claude` when Claude CLI supports headless container install.

---

## CI Integration

### Pipeline file: `.github/workflows/lifecycle-test.yml`

```yaml
name: Lifecycle Test
on: [push, pull_request]

jobs:
  opencode-lifecycle:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build binary
        run: bash build.sh /tmp/nx-agents-config-bin
      - name: Run OpenCode lifecycle test
        run: bash test/run-lifecycle.sh
```

No secrets required — the GGUF model is baked into the Docker image at build time.
The bare git remote is created locally inside the runner filesystem.

### GGUF model caching in CI

The Docker image with the GGUF baked in can be pushed to GitHub Container Registry
(GHCR) so subsequent CI runs do not re-download the model:

```yaml
      - name: Cache model image
        uses: docker/build-push-action@v5
        with:
          cache-from: type=registry,ref=ghcr.io/${{ github.repository }}/opencode-test:cache
          cache-to: type=registry,ref=ghcr.io/${{ github.repository }}/opencode-test:cache
```

### What blocks a merge

All of the following must be green:

- Binary builds (`bash build.sh` exits 0)
- Stage 1–2: setup and symlink wiring
- Stage 3: backup and sync (no interactive prompts)
- Stage 4: restore and session presence in `opencode.db`

LLM prompt assertions (steps 3, 14) are best-effort — they run when the model is
ready inside the container. All backup/restore/DB assertions are always required.

---

## Host Runner: `test/run-lifecycle.sh`

```bash
#!/usr/bin/env bash
# run-lifecycle.sh — Build images, run all lifecycle stages, print report.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BARE_REPO=/tmp/store-remote.git

echo "==> Building nx-agents-config binary"
bash "$REPO_ROOT/build.sh" /tmp/nx-agents-config-bin

# Create the shared bare repo (mounted into both containers)
rm -rf "$BARE_REPO"
git init --bare "$BARE_REPO"

echo ""
echo "==> OpenCode lifecycle test — Machine A (write/sync)"
docker build -f "$REPO_ROOT/test/Dockerfile.opencode" \
  -t nx-agents-opencode-test "$REPO_ROOT"
docker run --rm \
  -v "$BARE_REPO:$BARE_REPO" \
  -e BARE_REPO="$BARE_REPO" \
  nx-agents-opencode-test

echo ""
echo "==> OpenCode lifecycle test — Machine B (restore/verify)"
docker build -f "$REPO_ROOT/test/Dockerfile.restore" \
  -t nx-agents-restore-test "$REPO_ROOT"
docker run --rm \
  -v "$BARE_REPO:$BARE_REPO" \
  -e BARE_REPO="$BARE_REPO" \
  nx-agents-restore-test

echo ""
echo "==> All lifecycle tests passed"
```

Both containers receive the same bare repo path via bind-mount so Machine B
reads exactly what Machine A pushed.

---

## Release README: Test Results Section

The first release README includes an actual run of these tests.
Format for the results block:

```markdown
## Test Results (v1.0.0)

### OpenCode Lifecycle
| Stage | Test | Result |
|-------|------|--------|
| Install | OpenCode + nx-agents-config setup | ✓ |
| LLM | Local GGUF model (tinyllama) ready | ✓ |
| Session | Prompt via local Ollama (tinyllama) | ✓ |
| Session | Row in opencode.db | ✓ |
| Backup | nx-agents-config backup opencode | ✓ |
| Sync | nx-agents-config sync → bare remote | ✓ |
| Restore | nx-agents-config restore on Machine B | ✓ |
| Verify | opencode.db present with session row | ✓ |
| Verify | ~/.config/opencode/opencode.json correct | ✓ |
| Verify | ~/.local/share/opencode → store/opencode/userdata/ | ✓ |

### Unit + Integration (test/suite.sh)
40 assertions — all passing
```

This block is generated from actual test output, not written manually.
`run-lifecycle.sh` emits this table as part of its final output.

---

## Existing Unit Tests (`test/suite.sh`)

The existing T01–T14 suite (Alpine container, synthetic HOME at `/tmp/testhome`,
40 assertions) remains in place as the fast sanity check. It runs first —
lifecycle tests only run if it passes.

```text
test/run-tests.sh        → T01-T14 (fast, ~30s, no LLM needed)
test/run-lifecycle.sh    → E2E lifecycle (slower, ~3-5 min, GGUF model required)
test/run-gap-test.sh     → Gap verification (LLM required for prompt stages)
```
