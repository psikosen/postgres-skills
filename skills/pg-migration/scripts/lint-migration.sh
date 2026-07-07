#!/usr/bin/env bash
# lint-migration.sh — static safety lint for versioned SQL migration scripts.
#   Usage: lint-migration.sh <file.sql> [more.sql ...]
# Exit codes: 0 = clean (warnings allowed), 1 = blockers found, 2 = usage error.
#
# BLOCKERS are patterns that have caused real incidents (crash-looping deploys,
# destroyed data, unreadable rows). WARNINGS need a human decision, not a rewrite.
set -euo pipefail

[[ $# -ge 1 ]] || { echo "Usage: lint-migration.sh <file.sql> [...]" >&2; exit 2; }

blockers=0
warnings=0

blocker() { echo "  BLOCKER: $1"; blockers=$((blockers + 1)); }
warning() { echo "  warning: $1"; warnings=$((warnings + 1)); }

for f in "$@"; do
  [[ -f "$f" ]] || { echo "ERROR: no such file: $f" >&2; exit 2; }
  echo "== $f =="
  base="$(basename "$f")"
  # Strip line comments for pattern checks (block comments left in — rare in migrations).
  sql="$(sed 's/--.*$//' "$f")"
  upper="$(printf '%s' "$sql" | tr '[:lower:]' '[:upper:]')"

  # Naming convention: ScriptNNNN_Description.sql
  if [[ ! "$base" =~ ^Script[0-9]{4}_[A-Za-z0-9_-]+\.sql$ ]]; then
    warning "filename doesn't match ScriptNNNN_Description.sql — runner may ignore or misorder it"
  fi

  # DELETE / UPDATE without WHERE (whole-statement scan, per semicolon-separated stmt)
  while IFS= read -r stmt; do
    s="$(printf '%s' "$stmt" | tr '[:lower:]' '[:upper:]')"
    if [[ "$s" =~ ^[[:space:]]*DELETE[[:space:]]+FROM ]] && [[ ! "$s" =~ WHERE ]]; then
      blocker "DELETE without WHERE"
    fi
    if [[ "$s" =~ ^[[:space:]]*UPDATE[[:space:]] ]] && [[ ! "$s" =~ WHERE ]]; then
      blocker "UPDATE without WHERE"
    fi
  done < <(printf '%s' "$sql" | tr '\n' ' ' | tr ';' '\n')

  # CONCURRENTLY cannot run inside a transaction; most runners wrap scripts in one.
  if [[ "$upper" == *"CONCURRENTLY"* ]]; then
    blocker "CREATE/DROP INDEX CONCURRENTLY cannot run inside a transaction — flag this script for the runner's no-transaction mode or build the index out-of-band"
  fi

  # Heavy index builds: remind about per-statement timeout (timed-out unjournaled
  # scripts re-run and crash-loop every deploy).
  if [[ "$upper" == *"CREATE INDEX"* ]] && [[ "$upper" != *"CONCURRENTLY"* ]]; then
    warning "plain CREATE INDEX blocks writes and can exceed the runner's statement timeout on large tables — verify table size and the runner's execution timeout"
  fi

  # GIN/trigram builds are the classic timeout case.
  if [[ "$upper" == *"USING GIN"* ]]; then
    warning "GIN index build — the slowest index type; measure on a production-sized table before merging"
  fi

  # Destructive DDL
  for pat in "DROP TABLE" "DROP COLUMN" "TRUNCATE"; do
    if [[ "$upper" == *"$pat"* ]]; then
      warning "$pat — destructive; confirm with the ticket owner and capture row/usage evidence first"
    fi
  done

  # NOT NULL added without a DEFAULT (fails on any existing row).
  # Regexes kept in variables: an unquoted ';' inside [[ =~ ]] breaks bash parsing.
  re_notnull='ADD[[:space:]]+COLUMN[^;]*NOT[[:space:]]+NULL'
  re_default='ADD[[:space:]]+COLUMN[^;]*DEFAULT'
  if [[ "$upper" =~ $re_notnull ]] && [[ ! "$upper" =~ $re_default ]]; then
    warning "ADD COLUMN ... NOT NULL without DEFAULT — fails if the table has rows"
  fi

  # CHECK constraint value lists must be mirrored app-side.
  if [[ "$upper" == *"CHECK ("* || "$upper" == *"CHECK("* ]]; then
    warning "CHECK constraint — diff the allowed values against the application enum/converter in the same MR (a DB-legal value the app can't parse breaks every reader)"
  fi

  # Enum alterations can't run in a transaction pre-PG12 semantics for some ops.
  if [[ "$upper" == *"ALTER TYPE"* && "$upper" == *"ADD VALUE"* ]]; then
    warning "ALTER TYPE ... ADD VALUE — cannot run inside a transaction block on older Postgres; verify runner behavior"
  fi
done

echo ""
echo "Result: $blockers blocker(s), $warnings warning(s)"
[[ $blockers -eq 0 ]] || exit 1
