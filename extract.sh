#!/usr/bin/env bash
set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure lune is in PATH, checking common Rokit install location
if ! command -v lune &>/dev/null; then
    if [ -x "$HOME/.rokit/bin/lune" ]; then
        export PATH="$HOME/.rokit/bin:$PATH"
    elif command -v rokit &>/dev/null; then
        echo "[INFO] Running 'rokit install' to install managed tools..."
        (cd "$SCRIPT_DIR" && rokit install)
        if [ -x "$HOME/.rokit/bin/lune" ]; then
            export PATH="$HOME/.rokit/bin:$PATH"
        fi
    fi
fi

if ! command -v lune &>/dev/null; then
    echo "[ERROR] 'lune' command could not be found." >&2
    echo "Please ensure Rokit or Lune is installed:" >&2
    echo "  Rokit: https://github.com/rojo-rbx/rokit" >&2
    echo "  Lune:  https://lune-org.github.io/docs/" >&2
    exit 1
fi

exec lune run "$SCRIPT_DIR/extract.luau" "$@"
