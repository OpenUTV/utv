#!/bin/bash
#
# OpenUTV Version Update Checker
# Checks GitHub Releases API for new OpenUTV releases and prompts the user.
#

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CURRENT_VERSION=""

# Try reading version from Info.plist
if [ -f "${APP_DIR}/Info.plist" ]; then
    CURRENT_VERSION=$(defaults read "${APP_DIR}/Info.plist" CFBundleShortVersionString 2>/dev/null || true)
fi

# Fallback to binary -version
if [ -z "${CURRENT_VERSION}" ]; then
    BIN_DIR="$(dirname "$0")"
    if [ -x "${BIN_DIR}/UTV" ]; then
        CURRENT_VERSION=$("${BIN_DIR}/UTV" -version 2>/dev/null | tr -d '\n' || echo "2026.2")
    else
        CURRENT_VERSION="2026.2"
    fi
fi

RELEASE_DATA=$(curl -s -m 3 https://api.github.com/repos/OpenUTV/utv/releases/latest 2>/dev/null || true)
LATEST_TAG=$(echo "${RELEASE_DATA}" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "${LATEST_TAG}" ]; then
    if [ "$1" == "--interactive" ]; then
        osascript -e 'display alert "OpenUTV Updates" message "Unable to check for updates at this time. Please check your internet connection." as warning' 2>/dev/null || true
    fi
    exit 0
fi

# Normalize versions for comparison (strip leading 'v')
NORM_CURRENT="${CURRENT_VERSION#v}"
NORM_LATEST="${LATEST_TAG#v}"

# Version comparison function (returns 0 / true if $1 > $2)
version_gt() {
    test "$(printf '%s\n' "$1" "$2" | sort -V | head -n 1)" != "$1"
}

if version_gt "${NORM_LATEST}" "${NORM_CURRENT}"; then
    # Newer version available!
    HAS_CASK=0
    if [ -x "/opt/homebrew/bin/brew" ] && /opt/homebrew/bin/brew list --cask utv &>/dev/null; then
        HAS_CASK=1
    elif [ -x "/usr/local/bin/brew" ] && /usr/local/bin/brew list --cask utv &>/dev/null; then
        HAS_CASK=1
    fi

    if [ "${HAS_CASK}" -eq 1 ]; then
        CHOICE=$(osascript -e "button returned of (display alert \"OpenUTV Update Available\" message \"OpenUTV ${LATEST_TAG} is now available (you are currently running ${CURRENT_VERSION}). Would you like to upgrade now via Homebrew?\" buttons {\"Upgrade via Homebrew\", \"View on GitHub\", \"Later\"} default button 1)" 2>/dev/null || echo "Later")
        if [ "${CHOICE}" == "Upgrade via Homebrew" ]; then
            SCRIPT_PATH="/tmp/openutv_upgrade.command"
            cat << 'EOF' > "${SCRIPT_PATH}"
#!/bin/bash
clear 2>/dev/null || true
echo "================================================================="
echo "  Upgrading OpenUTV via Homebrew Cask..."
echo "================================================================="
echo ""
if [ -f "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
brew upgrade --cask utv
echo ""
echo "================================================================="
echo "  Upgrade finished! You can now restart OpenUTV."
echo "================================================================="
read -n 1 -s -r -p "Press any key to close..." && exit 0
EOF
            chmod 0755 "${SCRIPT_PATH}"
            open "${SCRIPT_PATH}"
        elif [ "${CHOICE}" == "View on GitHub" ]; then
            open "https://github.com/OpenUTV/utv/releases/latest"
        fi
    else
        CHOICE=$(osascript -e "button returned of (display alert \"OpenUTV Update Available\" message \"OpenUTV ${LATEST_TAG} is now available (you are currently running ${CURRENT_VERSION}).\" buttons {\"Download from GitHub\", \"Later\"} default button 1)" 2>/dev/null || echo "Later")
        if [ "${CHOICE}" == "Download from GitHub" ]; then
            open "https://github.com/OpenUTV/utv/releases/latest"
        fi
    fi
else
    if [ "$1" == "--interactive" ]; then
        osascript -e "display alert \"OpenUTV Updates\" message \"OpenUTV is up to date (version ${CURRENT_VERSION}).\" as informational" 2>/dev/null || true
    fi
fi

exit 0
