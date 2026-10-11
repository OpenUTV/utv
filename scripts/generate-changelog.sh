#!/usr/bin/env bash
set -euo pipefail

# Determine range of commits
TARGET_REF="${1:-HEAD}"
PREV_TAG="${2:-}"

if [ -z "$PREV_TAG" ]; then
  # Find the most recent release tag (YYYY.N) before TARGET_REF. Only release
  # tags count: the rolling dev-build tag moves with every development build,
  # and matching it would list only the commits since the previous one.
  PREV_TAG=$(git describe --tags --abbrev=0 --match '[0-9][0-9][0-9][0-9].[0-9]*' "${TARGET_REF}^" 2>/dev/null || echo "")
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

format_section "Features" "feat(\([^)]+\))?:"
format_section "Bug Fixes" "fix(\([^)]+\))?:"
format_section "Performance Improvements" "perf(\([^)]+\))?:"
format_section "Refactoring" "refactor(\([^)]+\))?:"
format_section "Code Style" "style(\([^)]+\))?:"
format_section "Build & Dependencies" "build(\([^)]+\))?:"
format_section "CI/CD" "ci(\([^)]+\))?:"
format_section "Documentation" "docs(\([^)]+\))?:"
format_section "Tests" "test(\([^)]+\))?:"
format_section "Chores" "chore(\([^)]+\))?:"

# Check for non-conventional or unclassified commits
OTHER=$(git log --pretty=format:"* %s (%h)" "$RANGE" | grep -v -E "^\* (feat|fix|perf|refactor|style|build|ci|docs|test|chore)(\([^)]+\))?:" || true)
if [ -n "$OTHER" ]; then
  echo "### Other Changes"
  echo "$OTHER"
  echo ""
fi

# Contributors: the humans who authored or co-authored commits, as
# "@login (Name)". The login comes from a GitHub noreply address, or from the
# GitHub API when GH_TOKEN and GITHUB_REPOSITORY are set (as in CI); otherwise
# just the name is shown. The list is humans only: bots, and AI coding tools
# that sign commits as authors or co-authors, are left out.

login_from_email() {
  # 12345+login@users.noreply.github.com or login@users.noreply.github.com
  case "$1" in
    *@users.noreply.github.com) echo "${1%@users.noreply.github.com}" | sed 's/^[0-9]*+//' ;;
  esac
}

# $1 is "Name <email>". Matching is case-insensitive and uses the exact names
# and addresses these tools sign with, so people who happen to be called Claude
# or Jules, or who work at Google, are still credited.
is_excluded() {
  local who
  who=$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')
  case "$who" in
    *"[bot]"*) return 0 ;;                                          # GitHub Apps and bot accounts
    *@anthropic.com* | "claude <"* | "claude code <"* | "claude opus "* | "claude sonnet "* | "claude haiku "* | "claude fable "*)
      return 0 ;;                                                    # Claude, Claude Code
    *@openai.com* | "codex <"* | "chatgpt <"* | "chatgpt codex"*) return 0 ;;   # OpenAI Codex
    "copilot <"* | *+copilot@users.noreply.github.com*) return 0 ;;  # GitHub Copilot coding agent
    *@cursor.com* | *@cursor.sh*) return 0 ;;                         # Cursor
    *@aider.chat*) return 0 ;;                                       # Aider
    *@cognition.ai* | *devin-ai-integration*) return 0 ;;             # Devin
    "gemini-code-assist"* | "google-labs-jules"*) return 0 ;;        # Gemini Code Assist, Jules
  esac
  return 1
}

# One "login<TAB>name" line per author or co-author; login may be empty.
PEOPLE=""

add_contributor() {
  local name="$1" email="$2" login="$3"
  is_excluded "$name <$email>" && return
  [ -z "$login" ] && login=$(login_from_email "$email")
  PEOPLE+="${login}"$'\t'"${name}"$'\n'
}

while IFS=$'\t' read -r sha name email; do
  [ -z "$sha" ] && continue
  login=""
  if [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && command -v gh >/dev/null 2>&1; then
    # "login<TAB>type"; skip accounts GitHub itself marks as bots.
    info=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${sha}" --jq '[.author.login // "", .author.type // ""] | @tsv' 2>/dev/null || true)
    login="${info%%$'\t'*}"
    [ "${info#*$'\t'}" = "Bot" ] && continue
  fi
  add_contributor "$name" "$email" "$login"
done < <(git log "$RANGE" --format="%H%x09%aN%x09%aE")

while IFS= read -r trailer; do
  [ -z "$trailer" ] && continue
  name="${trailer% <*}"
  email=$(echo "$trailer" | sed -n 's/.*<\(.*\)>.*/\1/p')
  add_contributor "$name" "$email" ""
done < <(git log "$RANGE" --format="%(trailers:key=Co-authored-by,valueonly=true)")

# Keep one line per person, in order of first appearance. A name seen without
# a login (a commit from an address not linked to GitHub) merges into the same
# name's @login entry.
CONTRIBUTOR_LINES=$(printf "%s" "$PEOPLE" | awk -F'\t' '
  NF == 0 { next }
  { key = tolower($1 != "" ? $1 : $2); name = tolower($2) }
  $1 != "" { if (!(key in seen)) { seen[key] = 1; order[++n] = "* @" $1 " (" $2 ")"; named[name] = 1 } ; next }
  { pending[++m] = $2 }
  END {
    for (i = 1; i <= n; i++) print order[i]
    for (i = 1; i <= m; i++) { k = tolower(pending[i]); if (!(k in named) && !(k in done)) { done[k] = 1; print "* " pending[i] } }
  }')

if [ -n "$CONTRIBUTOR_LINES" ]; then
  echo "### Contributors"
  echo "Special thanks to all contributors who worked on this release:"
  echo ""
  echo "$CONTRIBUTOR_LINES"
  echo ""
fi
