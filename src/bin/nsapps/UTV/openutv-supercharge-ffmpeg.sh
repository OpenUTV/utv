#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "${DIR}/py-interp" ]; then
    exec "${DIR}/py-interp" "${DIR}/openutv-supercharge-ffmpeg.py" "$@"
elif command -v python3 &>/dev/null; then
    exec python3 "${DIR}/openutv-supercharge-ffmpeg.py" "$@"
else
    exec python "${DIR}/openutv-supercharge-ffmpeg.py" "$@"
fi
