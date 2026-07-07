#!/usr/bin/env bash
# explain.sh — EXPLAIN (ANALYZE, BUFFERS) inside a rolled-back transaction.
#   Usage: explain.sh <env> "<sql>"
# ANALYZE executes the statement for real, so DML is wrapped in BEGIN…ROLLBACK:
# measured, then undone. Same ~/.claude/pg.env environment registry as psql-ro.sh.
set -euo pipefail

PG_ENV_FILE="${PG_ENV_FILE:-$HOME/.claude/pg.env}"
TIMEOUT_MS="${PG_TIMEOUT_MS:-30000}"

if [[ $# -lt 2 ]]; then
  echo "Usage: explain.sh <env> \"<sql>\"" >&2
  exit 2
fi
if [[ ! -f "$PG_ENV_FILE" ]]; then
  echo "ERROR: $PG_ENV_FILE not found (see pg.env.example in the Postgres toolkit)." >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$PG_ENV_FILE"

ENV_NAME="$1"; SQL="$2"
if ! declare -F "pg_env_${ENV_NAME}" >/dev/null; then
  echo "ERROR: environment '$ENV_NAME' not defined in $PG_ENV_FILE" >&2
  exit 2
fi
"pg_env_${ENV_NAME}"

export PGSSLMODE="${PGSSLMODE:-require}"
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
export PGOPTIONS="-c statement_timeout=${TIMEOUT_MS} -c application_name=claude-pg-explain"

# Single session: BEGIN, plan, ROLLBACK. ON_ERROR_STOP aborts (and thus rolls
# back) on any failure, so no partial effects can survive.
psql -X -q -v ON_ERROR_STOP=1 -P pager=off <<SQLEOF
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) ${SQL};
ROLLBACK;
SQLEOF
