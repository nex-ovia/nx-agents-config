#!/usr/bin/env bash
# run-tests.sh — Build Docker image and run the container test suite.
# Usage:
#   bash test/run-tests.sh          # run all tests, remove container on exit
#   bash test/run-tests.sh --keep   # keep container alive after failure for debugging
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="nx-agents-test"
CONTAINER="nx-agents-test-run"
KEEP=false

for arg in "$@"; do
  [[ "$arg" == "--keep" ]] && KEEP=true
done

echo "==> Building Docker image: $IMAGE"
docker build -f "$REPO_ROOT/test/Dockerfile" -t "$IMAGE" "$REPO_ROOT"

echo ""
echo "==> Running test suite inside container"

if $KEEP; then
  docker run --name "$CONTAINER" "$IMAGE" || {
    echo ""
    echo "Tests FAILED. Container '$CONTAINER' is still running for debugging."
    echo "  docker exec -it $CONTAINER bash"
    echo "  docker rm -f $CONTAINER   # when done"
    exit 1
  }
  docker rm "$CONTAINER" 2>/dev/null || true
else
  docker run --rm "$IMAGE"
fi

echo ""
echo "==> All tests passed."
