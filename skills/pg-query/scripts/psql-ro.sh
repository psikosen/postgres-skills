#!/usr/bin/env bash
# psql-ro.sh — guarded read-only psql for shared environments.
#   Usage: psql-ro.sh <env> "<sql>"        run a query
#          psql-ro.sh                      list configured environments
#
# Environments are defined in ~/.claude/pg.env as shell functions or vars:
#   pg_env_<name>() { export PGHOST=... PGDATABASE=... PGUSER=... PGPASSWORD=...; }
# or a resolver that fetches credentials on demand (KeyVault, vault, etc.).
# See pg.env.example shipped alongside this toolkit.
set -euo pipefail

PG_ENV_FILE="${PG_ENV_FILE:-$HOME/.claude/pg.env}"
TIMEOUT_MS="${PG_TIMEOUT_MS:-15000}"

if [[ ! -f "$PG_ENV_FILE" ]]; then
  echo "ERROR: $PG_ENV_FILE not found. Copy pg.env.example from the Postgres toolkit" >&2
  echo "to ~/.claude/pg.env and define your environments." >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$PG_ENV_FILE"

if [[ $# -lt 1 ]]; then
  echo "Configured environments:"
  declare -F | awk '{print $3}' | grep '^pg_env_' | sed 's/^pg_env_/  /' || true
  exit 0
fi

ENV_NAME="$1"; shift
SQL="${1:-}"
if [[ -z "$SQL" ]]; then
  echo "ERROR: no SQL given. Usage: psql-ro.sh <env> \"<sql>\"" >&2
  exit 2
fi

if ! declare -F "pg_env_${ENV_NAME}" >/dev/null; then
  echo "ERROR: environment '$ENV_NAME' not defined in $PG_ENV_FILE" >&2
  exit 2
fi
"pg_env_${ENV_NAME}"

export PGSSLMODE="${PGSSLMODE:-require}"
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
# Session-level guards: read-only + bounded runtime. Belt, not a jail — the
# CLAUDE.md rules forbid attempting to lift these.
export PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=${TIMEOUT_MS} -c application_name=claude-pg-query"

exec psql -X -q -v ON_ERROR_STOP=1 -P pager=off -c "$SQL"
