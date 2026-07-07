#!/usr/bin/env bash
# SessionStart hook — one-line drift nag.
# Runs install.sh --check against the repo named by PG_TOOLKIT_REPO in
# ~/.claude/pg.env. Prints only OUTDATED/DRIFTED lines; stays silent when
# everything is current, so healthy sessions cost nothing.
set -uo pipefail

source "$HOME/.claude/pg.env" 2>/dev/null || exit 0
[[ -n "${PG_TOOLKIT_REPO:-}" ]] || exit 0

# The repo may be the toolkit itself or a parent containing Postgres/.
REPO_DIR=""
if [[ -x "$PG_TOOLKIT_REPO/install.sh" && -f "$PG_TOOLKIT_REPO/VERSION" ]]; then
  REPO_DIR="$PG_TOOLKIT_REPO"
elif [[ -x "$PG_TOOLKIT_REPO/Postgres/install.sh" ]]; then
  REPO_DIR="$PG_TOOLKIT_REPO/Postgres"
fi
[[ -n "$REPO_DIR" ]] || exit 0

ISSUES="$("$REPO_DIR/install.sh" --check 2>/dev/null | grep -E 'OUTDATED|DRIFTED' || true)"
if [[ -n "$ISSUES" ]]; then
  echo "Postgres toolkit needs attention (run /pg-toolkit check):"
  echo "$ISSUES"
fi
exit 0
