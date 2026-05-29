#!/usr/bin/env bash
set -euo pipefail

OUTPUT="${1:-nx-agents-config}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$ROOT/src"

# Encode default TOML as a single-line base64 string (portable across macOS/Linux)
DEFAULT_TOML_B64=$(base64 < "$ROOT/nx-agents.toml" | tr -d '\n')

{
    # ── Header ──
    echo '#!/usr/bin/env bash'
    echo '# nx-agents-config — Self-contained binary'
    echo '# https://github.com/nex-ovia/nx-agents-config'
    echo 'set -euo pipefail'
    echo

    # ── Config home ──
    echo '# Directory where store/ and shared/ live'
    echo 'NX_AGENTS_HOME="${HOME}/.nx-agents-config"'
    echo

    # ── Embedded TOML ──
    echo '# Embedded default TOML (base64 encoded)'
    echo "DEFAULT_TOML_B64='${DEFAULT_TOML_B64}'"
    echo

    # ── Decode embedded TOML at startup ──
    echo '# Decode embedded default TOML'
    echo 'DEFAULT_TOML=$(python3 -c "import base64,sys; sys.stdout.write(base64.b64decode(sys.argv[1]).decode())" "$DEFAULT_TOML_B64" 2>/dev/null || printf "")'
    echo

    # ── Libraries ──
    for lib in colors toml backup symlink util; do
        grep -v '^source ' "$SRC_DIR/lib/${lib}.sh"
        echo
    done

    # ── Commands ──
    for cmd in tree setup update sync project tool backup restoreFromBkp restore update-tool uninstall; do
        grep -v '^source ' "$SRC_DIR/commands/${cmd}.sh"
        echo
    done

    # ── Dispatcher (main.sh without source lines) ──
    grep -v '^source ' "$SRC_DIR/main.sh"

} > "$OUTPUT"

chmod +x "$OUTPUT"
echo "Built: $OUTPUT ($(wc -c < "$OUTPUT") bytes)"
