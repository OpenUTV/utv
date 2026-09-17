#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "${DIR}/py-interp" ]; then
    exec "${DIR}/py-interp" "${DIR}/openutv-diagnostics.py" "$@"
elif command -v python3 &>/dev/null; then
    exec python3 "${DIR}/openutv-diagnostics.py" "$@"
else
    exec python "${DIR}/openutv-diagnostics.py" "$@"
fi
