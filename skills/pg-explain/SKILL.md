---
name: pg-explain
version: 1.2.0
description: Get and interpret EXPLAIN (ANALYZE, BUFFERS) plans safely (DML analyzed inside a rolled-back transaction). Required evidence before any index add, query rewrite, or "fixed the slow query" claim.
when_to_use: Use for any query-performance question — "why is this slow", "does this use the index", "should we add an index" — and before/after every performance change. Also when a /pg-query hits the statement timeout.
argument-hint: "[env] [sql]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/explain.sh *)
---

# pg-explain — plans, safely, then an honest reading

```bash
${CLAUDE_SKILL_DIR}/scripts/explain.sh <env> "<sql>"
```

The wrapper runs `EXPLAIN (ANALYZE, BUFFERS)` inside `BEGIN … ROLLBACK`, so analyzing
an UPDATE/DELETE is safe (executed, measured, rolled back). Uses the same `~/.claude/pg.env`
environments as `/pg-query`. `PG_TIMEOUT_MS` overrides the 30s default.

## How to read the plan — check these in order

1. **Actual vs estimated rows.** Off by >10× → stale stats or a correlation the planner
   can't see; the rest of the plan is built on that mistake. (`ANALYZE <table>` may be
   the whole fix — via a migration, not ad hoc.)
2. **Seq Scan on a large table under a filter** → the predicate is unindexed or
   non-sargable. Classic non-sargable shapes: leading-wildcard `LIKE '%x%'` (needs a
   trigram GIN on `lower(col)` — and even that can't serve patterns with <3 useful
   trigram chars), `function(col) = …` without a matching expression index,
   type-mismatched comparisons.
3. **Index Scan Backward + LIMIT ("abort-early")** — fast when matches are recent and
   abundant, catastrophic when sparse: it walks the index until the page fills. If actual
   time is huge with few returned rows, this is why. The bitmap alternative
   (materialize matches, top-N sort) has the opposite failure mode on very hot terms.
   There is often **no single plan good for all inputs** — say so instead of picking a
   plan that's fast on your one test value.
4. **Buffers:** `read` ≫ `hit` means cold/oversized working set; a huge `Rows Removed by
   Filter` means the index isn't selective for this predicate.
5. **Sorts spilling** (`external merge Disk`) → work_mem, or an index providing the order.

## Discipline

- **Before/after or it didn't happen.** Capture the plan before the change and after,
  on realistic data volume (the small dev DB lies — say which env the plan came from).
- **An index is a write tax.** Recommend one only when the plan shows the scan, and name
  the exact definition (columns, order, partial predicate, `text_pattern_ops`/GIN as
  appropriate). Index creation goes in a migration (`/pg-migration`), never ad hoc —
  and for large tables note the `CREATE INDEX CONCURRENTLY` / build-timeout caveats
  the migration skill enforces.
