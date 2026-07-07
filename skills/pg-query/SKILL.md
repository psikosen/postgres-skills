---
name: pg-query
version: 1.1.0
description: Run ad-hoc READ-ONLY SQL against a Postgres environment through a guarded wrapper (read-only session, statement timeout, row cap). The ONLY sanctioned way to query shared databases from a session.
when_to_use: Use whenever you or the user need to look at live data — "check the DB", "query prod/beta/dev", "how many rows...", "what's in table X". Also use instead of raw psql in any verification step.
argument-hint: "[env] [sql or a question to translate into sql]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/psql-ro.sh *)
---

# pg-query — guarded read-only querying

Run every query through the bundled wrapper — never raw `psql`:

```bash
${CLAUDE_SKILL_DIR}/scripts/psql-ro.sh <env> "<sql>"
```

- `<env>` is a name defined in `~/.claude/pg.env` (e.g. `dev`, `beta`). Run the script
  with no args to list configured environments. If the env the user wants is missing,
  show them `~/.claude/pg.env.example` and stop — do not improvise a connection string.
- The wrapper enforces: `default_transaction_read_only=on`, `statement_timeout` (15s
  default, `PG_TIMEOUT_MS` to override), and appends `LIMIT 500` guidance — add an
  explicit `LIMIT` to exploratory `SELECT *` yourself.

## Rules

1. **Reads only.** If the task turns out to need a write, stop and tell the user; writes
   belong in a migration (`/pg-migration`) or an explicitly user-approved transaction.
2. **Translate questions to SQL, show the SQL.** When the user asks in English, print the
   SQL you ran alongside the result so it's auditable.
3. **Big tables:** filter or aggregate; never `SELECT *` an unbounded table. If a count
   is enough, count.
4. **PII:** when results contain emails/names and the user only needs counts or ids,
   project the narrow columns.

## Failure modes

- `statement canceled` → the query blew the timeout. Don't just retry: either narrow it
  or switch to `/pg-explain` to see why it's slow.
- `cannot execute ... in a read-only transaction` → working as intended; see rule 1.
