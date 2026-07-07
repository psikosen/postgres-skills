#!/usr/bin/env bash
# bump.sh — set the toolkit version EVERYWHERE it appears, in one command.
#   Usage: ./bump.sh 1.1.0
# Updates: VERSION, every SKILL.md / agent frontmatter `version:`, and the
# CLAUDE.md.fragment begin-marker. This is the only sanctioned way to bump —
# hand-editing one of the three places is how drift starts.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

NEW="${1:-}"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: ./bump.sh <semver>  e.g. ./bump.sh 1.1.0" >&2; exit 2; }

OLD="$(cat VERSION)"
echo "$NEW" > VERSION

for f in skills/*/SKILL.md agents/*.md commands/*.md; do
  sed -i '' "s/^version: .*/version: $NEW/" "$f"
done

sed -i '' "s/^# --- Postgres toolkit (optional add-on) v[0-9.]* ---$/# --- Postgres toolkit (optional add-on) v$NEW ---/" CLAUDE.md.fragment

echo "Bumped $OLD -> $NEW:"
grep -rH "^version:" skills/*/SKILL.md agents/*.md commands/*.md
head -1 CLAUDE.md.fragment
echo ""
echo "Next: commit, then teammates re-run ./install.sh (the block upgrades in place)."
