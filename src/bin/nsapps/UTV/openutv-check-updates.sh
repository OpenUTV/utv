#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "${DIR}/py-interp" ]; then
    exec "${DIR}/py-interp" "${DIR}/openutv-check-updates.py" "$@"
elif command -v python3 &>/dev/null; then
    exec python3 "${DIR}/openutv-check-updates.py" "$@"
else
    exec python "${DIR}/openutv-check-updates.py" "$@"
fi
