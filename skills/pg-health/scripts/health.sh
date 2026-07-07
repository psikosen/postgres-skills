#!/usr/bin/env bash
# health.sh — read-only Postgres health snapshot.
#   Usage: health.sh <env>
# Same ~/.claude/pg.env environment registry as psql-ro.sh; read-only session,
# every section independently bounded so one slow view can't kill the report.
set -euo pipefail

PG_ENV_FILE="${PG_ENV_FILE:-$HOME/.claude/pg.env}"
TIMEOUT_MS="${PG_TIMEOUT_MS:-20000}"

[[ $# -ge 1 ]] || { echo "Usage: health.sh <env>" >&2; exit 2; }
[[ -f "$PG_ENV_FILE" ]] || { echo "ERROR: $PG_ENV_FILE not found (see pg.env.example)." >&2; exit 2; }
# shellcheck disable=SC1090
source "$PG_ENV_FILE"

ENV_NAME="$1"
declare -F "pg_env_${ENV_NAME}" >/dev/null || { echo "ERROR: environment '$ENV_NAME' not defined in $PG_ENV_FILE" >&2; exit 2; }
"pg_env_${ENV_NAME}"

export PGSSLMODE="${PGSSLMODE:-require}"
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
export PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=${TIMEOUT_MS} -c application_name=claude-pg-health"

run() { # run "title" "sql" — a failing section prints its error and moves on
  echo ""
  echo "=== $1 ==="
  psql -X -q -v ON_ERROR_STOP=0 -P pager=off -c "$2" || echo "(section failed — see above)"
}

run "Server / database" "
SELECT version(), current_database() AS db, pg_size_pretty(pg_database_size(current_database())) AS db_size;"

run "Connections vs max" "
SELECT (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max_conn,
       count(*) AS current,
       count(*) FILTER (WHERE state <> 'idle') AS active
FROM pg_stat_activity;"

run "Connections by application" "
SELECT coalesce(application_name,'(none)') AS app, state, count(*)
FROM pg_stat_activity GROUP BY 1,2 ORDER BY 3 DESC LIMIT 15;"

run "Oldest transactions (vacuum blockers)" "
SELECT pid, usename, state, application_name,
       now() - xact_start AS xact_age, left(query, 80) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start LIMIT 5;"

run "Largest relations" "
SELECT relname, pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
       pg_size_pretty(pg_relation_size(c.oid)) AS table_size
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog','information_schema') AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 15;"

run "Seq-scan hot spots (large tables scanned sequentially)" "
SELECT relname, seq_scan, idx_scan, n_live_tup,
       pg_size_pretty(pg_relation_size(relid)) AS size
FROM pg_stat_user_tables
WHERE seq_scan > 0 AND n_live_tup > 10000
ORDER BY seq_scan * n_live_tup DESC LIMIT 15;"

run "Unused indexes (idx_scan = 0)" "
SELECT s.relname AS table, s.indexrelname AS index,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS size
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.idx_scan = 0 AND NOT i.indisunique AND NOT i.indisprimary
ORDER BY pg_relation_size(s.indexrelid) DESC LIMIT 15;"

run "Cache hit ratio (want > 0.99)" "
SELECT round(sum(blks_hit)::numeric / nullif(sum(blks_hit) + sum(blks_read), 0), 4) AS cache_hit_ratio
FROM pg_stat_database WHERE datname = current_database();"

run "Autovacuum lag / dead tuples" "
SELECT relname, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup,0), 2) AS dead_ratio,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC LIMIT 10;"

run "Top statements by total time (needs pg_stat_statements)" "
SELECT round(total_exec_time::numeric, 0) AS total_ms, calls,
       round(mean_exec_time::numeric, 1) AS mean_ms,
       left(query, 110) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 10;"

echo ""
echo "=== end of report ==="
