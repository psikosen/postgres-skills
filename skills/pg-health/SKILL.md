---
name: pg-health
version: 1.1.0
description: One-shot Postgres health report for an environment — table/index sizes, sequential-scan hot spots, unused and duplicate indexes, cache hit ratio, connection saturation, autovacuum lag, and top statements when pg_stat_statements is available.
when_to_use: Use when the user reports database slowness, timeouts, connection errors, or asks "how is the DB doing" — and as the first move when triaging any perf incident before guessing at causes.
argument-hint: "[env]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/health.sh *)
context: fork
---

# pg-health — measure first, opine second

```bash
${CLAUDE_SKILL_DIR}/scripts/health.sh <env>
```

Read-only, statement-timeout-bounded, same `~/.claude/pg.env` registry as `/pg-query`.

## Deliverable

Summarize the raw sections into findings ranked by impact, each with the evidence line
that supports it. Do NOT dump the raw output at the user. Typical reads:

- **Seq-scan-heavy large table** (`seq_scan` high, `idx_scan` low, size big) → candidate
  for `/pg-explain` on the query that drives it; name the table and the likely predicate.
- **Unused index** (`idx_scan = 0`, nontrivial size) → drop candidate — but check
  replicas/reports before recommending; dropping is a migration.
- **Cache hit ratio < ~0.99** on a small-working-set app → memory pressure or one
  pathological query flushing the cache.
- **Connections near max** → pool misconfiguration or leak; list the top
  `application_name`s from the report.
- **Dead-tuple ratio high / last autovacuum old** → bloat; long-running transactions
  often the real culprit (they pin vacuum) — the report lists oldest transactions.
- **Top statements by total time** (when `pg_stat_statements` exists) → the actual
  candidates for `/pg-explain`; anything else is guessing.

End with at most three recommended next actions, each mapped to a skill
(`/pg-explain <env> "<the query>"`, a `/pg-migration` for an index, or "no action —
healthy") so the user can proceed in one step.
