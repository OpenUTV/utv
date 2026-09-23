#!/usr/bin/env bash
set -euo pipefail

# Determine range of commits
TARGET_REF="${1:-HEAD}"
PREV_TAG="${2:-}"

if [ -z "$PREV_TAG" ]; then
  # Find the most recent semantic release tag before TARGET_REF
  PREV_TAG=$(git describe --tags --abbrev=0 "${TARGET_REF}^" 2>/dev/null || echo "")
fi

if [ -n "$PREV_TAG" ]; then
  RANGE="${PREV_TAG}..${TARGET_REF}"
  echo "Generating changelog for range: ${RANGE}" >&2
else
  RANGE="${TARGET_REF}"
  echo "Generating changelog from repository start up to: ${RANGE}" >&2
fi

OUTPUT=""

format_section() {
  local title="$1"
  local pattern="$2"
  local commits
  commits=$(git log --pretty=format:"* %s (%h)" "$RANGE" | grep -E "^\* ${pattern}" || true)
  if [ -n "$commits" ]; then
    echo "### ${title}"
    echo "$commits"
    echo ""
  fi
}

format_section "✨ Features" "feat(\([^)]+\))?:"
format_section "🐛 Bug Fixes" "fix(\([^)]+\))?:"
format_section "⚡ Performance" "perf(\([^)]+\))?:"
format_section "♻️ Refactoring" "refactor(\([^)]+\))?:"
format_section "🎨 Code Style" "style(\([^)]+\))?:"
format_section "🏗️ Build & Dependencies" "build(\([^)]+\))?:"
format_section "🔧 CI/CD" "ci(\([^)]+\))?:"
format_section "📚 Documentation" "docs(\([^)]+\))?:"
format_section "🧪 Tests" "test(\([^)]+\))?:"
format_section "📦 Chores" "chore(\([^)]+\))?:"

# Check for non-conventional or unclassified commits
OTHER=$(git log --pretty=format:"* %s (%h)" "$RANGE" | grep -v -E "^\* (feat|fix|perf|refactor|style|build|ci|docs|test|chore)(\([^)]+\))?:" || true)
if [ -n "$OTHER" ]; then
  echo "### 🪵 Other Changes"
  echo "$OTHER"
  echo ""
fi
