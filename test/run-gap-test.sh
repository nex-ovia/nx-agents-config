#!/usr/bin/env bash
# run-gap-test.sh — Build the gap-test image and run the lifecycle gap test.
# The container needs network access to ami-lab.nex-ovia.com:11434 (Ollama).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="nx-agents-gap-test"

echo "==> Building gap test image (Debian + bun + opencode)"
docker build -f "$REPO_ROOT/test/Dockerfile.gap" -t "$IMAGE" "$REPO_ROOT"

echo ""
echo "==> Running gap test (Ollama at ami-lab.nex-ovia.com:11434)"
docker run --rm "$IMAGE"
