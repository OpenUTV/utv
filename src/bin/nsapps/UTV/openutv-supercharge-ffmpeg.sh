#!/bin/bash
# OpenUTV Supercharge FFmpeg Wrapper

# Ensure Homebrew environment is available
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv 2>/dev/null)"
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${DIR}/openutv-supercharge-ffmpeg.py"

if [ -x "${DIR}/py-interp" ]; then
    exec "${DIR}/py-interp" "${SCRIPT}" "$@"
elif [ -x "${DIR}/../MacOS/py-interp" ]; then
    exec "${DIR}/../MacOS/py-interp" "${SCRIPT}" "$@"
elif [ -x "${DIR}/../bin/py-interp" ]; then
    exec "${DIR}/../bin/py-interp" "${SCRIPT}" "$@"
elif command -v python3 &>/dev/null; then
    exec python3 "${SCRIPT}" "$@"
else
    exec python "${SCRIPT}" "$@"
fi
