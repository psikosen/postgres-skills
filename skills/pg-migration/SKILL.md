---
name: pg-migration
version: 1.0.0
description: Author and lint versioned SQL migrations (DbUp-style ScriptNNNN files) with the guardrails that have actually bitten this team — lock hazards, CONCURRENTLY-in-transaction, timeout blowups on index builds, constraint/enum drift.
when_to_use: Use for ANY schema change — new table/column/index, constraint change, data backfill, or repair script. Also when reviewing a diff that adds or edits a *.sql migration.
argument-hint: "[what the migration should do]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/lint-migration.sh *)
paths: "**/Scripts/*.sql, **/migrations/**"
---

# pg-migration — write it once, ship it everywhere

Migrations run unattended on every environment, in order, exactly once. Author
accordingly, then **always lint before committing**:

```bash
${CLAUDE_SKILL_DIR}/scripts/lint-migration.sh <path/to/ScriptNNNN_Name.sql>
```

## Authoring checklist

1. **Numbering & naming:** next free `ScriptNNNN_<Issue>_<WhatItDoes>.sql` in the
   migrations folder — check for a parallel branch that already claimed the number.
2. **Never edit a merged script.** The journal records it as applied; edits silently
   never run. Fix forward with a new script.
3. **Write against LIVE data, not seeds.** Templates/rows in real environments drift
   from seed files — when a migration rewrites content (email bodies, labels), build the
   UPDATE from what production actually contains and add a `WHERE` that proves it.
4. **Idempotence where cheap:** `IF NOT EXISTS` / `IF EXISTS`, guarded `UPDATE`s. The
   journal normally prevents re-runs, but a failed non-transactional script re-runs on
   the next boot — idempotence is what makes that safe.
5. **Locks:** `ALTER TABLE` takes ACCESS EXCLUSIVE. On hot tables prefer additive,
   multi-step paths (add nullable column → backfill in batches → add constraint
   `NOT VALID` → `VALIDATE CONSTRAINT`).
6. **Index builds on large tables:** plain `CREATE INDEX` blocks writes and can outlive
   the runner's per-statement timeout — a timed-out, unjournaled script **re-runs and
   crash-loops every deploy** while the platform reports success. Raise the execution
   timeout for heavy scripts, or build out-of-band with `CREATE INDEX CONCURRENTLY`
   (which cannot run inside a transaction — most runners wrap scripts in one; such
   scripts must be flagged for the runner's no-transaction mode).
7. **CHECK constraints must mirror application enums.** A DB-legal value the app can't
   parse takes down every reader of that table. When adding/altering a CHECK list, diff
   it against the app-side enum/converter in the same MR.
8. **Destructive ops** (`DROP`, `TRUNCATE`, `DELETE` without `WHERE`, type narrowing):
   call them out to the user explicitly before committing, with row-count evidence from
   `/pg-query`.
9. **One concern per script.** A repair backfill and a schema change are two scripts.

## Data-repair scripts

State the identification heuristic in a header comment (how you know exactly which rows
are broken and why healthy rows can't match), and prove it first with a
`BEGIN; <update>; SELECT …; ROLLBACK;` dry run via `/pg-query`'s env registry.

## Review

For anything beyond a trivial additive change, hand the diff to the **pg-reviewer**
agent before opening the MR.
