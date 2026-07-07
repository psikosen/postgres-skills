#!/usr/bin/env bash
# monitor.sh — one cheap read-only probe, key=value output.
#   Usage: monitor.sh <env>
# Six numbers a monitor needs, one round trip, hard 8s timeout. Same
# ~/.claude/pg.env registry as the other toolkit scripts.
set -euo pipefail

PG_ENV_FILE="${PG_ENV_FILE:-$HOME/.claude/pg.env}"
TIMEOUT_MS="${PG_TIMEOUT_MS:-8000}"

[[ $# -ge 1 ]] || { echo "error=usage: monitor.sh <env>"; exit 2; }
[[ -f "$PG_ENV_FILE" ]] || { echo "error=$PG_ENV_FILE not found"; exit 2; }
# shellcheck disable=SC1090
source "$PG_ENV_FILE"

ENV_NAME="$1"
declare -F "pg_env_${ENV_NAME}" >/dev/null || { echo "error=environment '$ENV_NAME' not in $PG_ENV_FILE"; exit 2; }
"pg_env_${ENV_NAME}"

export PGSSLMODE="${PGSSLMODE:-require}"
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
export PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=${TIMEOUT_MS} -c application_name=claude-pg-monitor"

psql -X -q -t -A -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'conn_pct=' || round(100.0 * count(*) / (SELECT setting::int FROM pg_settings WHERE name = 'max_connections'))
FROM pg_stat_activity;

SELECT 'oldest_xact_sec=' || coalesce(round(extract(epoch FROM now() - min(xact_start)))::text, '0')
FROM pg_stat_activity WHERE xact_start IS NOT NULL;

SELECT 'waiting_locks=' || count(*)
FROM pg_stat_activity WHERE wait_event_type = 'Lock';

SELECT 'cache_hit=' || coalesce(round(sum(blks_hit)::numeric / nullif(sum(blks_hit) + sum(blks_read), 0), 4)::text, '1')
FROM pg_stat_database WHERE datname = current_database();

SELECT 'worst_dead_ratio=' || coalesce(max(round(n_dead_tup::numeric / nullif(n_live_tup, 0), 2))::text, '0')
FROM pg_stat_user_tables WHERE n_live_tup > 1000;

SELECT 'longest_query_sec=' || coalesce(round(extract(epoch FROM now() - min(query_start)))::text, '0')
FROM pg_stat_activity WHERE state = 'active' AND pid <> pg_backend_pid();
SQL
