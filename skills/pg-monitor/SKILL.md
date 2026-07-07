---
name: pg-monitor
version: 1.5.0
description: Cheap scheduled Postgres monitor — one small read-only probe, one-line verdict. Runs on Haiku at low effort because the job is reading six numbers against thresholds, not thinking. Built to fire from a schedule (/loop, a scheduled task, or OS cron via claude -p); also fine to run by hand for a quick pulse check.
when_to_use: Use for recurring lightweight monitoring ("watch the DB", "check dev every 30 minutes") and quick is-anything-on-fire pulses. For an actual investigation use /pg-health (full report) or /pg-triage (live incident).
argument-hint: "[env]"
model: haiku
effort: low
context: fork
disallowed-tools: AskUserQuestion
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/monitor.sh *)
---

# pg-monitor — six numbers, one line

Run the probe (read-only, ~1s):

```bash
${CLAUDE_SKILL_DIR}/scripts/monitor.sh <env>
```

It prints `key=value` lines. Compare against these thresholds:

| key | warn when |
|---|---|
| conn_pct | > 80 (connections used, % of max) |
| oldest_xact_sec | > 300 (a transaction open > 5 min pins vacuum and locks) |
| waiting_locks | > 0 (sessions blocked on locks right now) |
| cache_hit | < 0.99 |
| worst_dead_ratio | > 0.2 (dead tuples vs live on the worst table) |
| longest_query_sec | > 120 |

## Verdict — exactly one line

- All within thresholds → `pg-monitor <env>: OK (conn 12%, oldest xact 3s)` — nothing else.
- Any threshold crossed → `pg-monitor <env>: WARN — <the crossed keys with values>`,
  then ONE sentence naming the follow-up (`/pg-triage <env>` for locks/connections,
  `/pg-health <env>` for the rest).
- Probe failed (bad env, network, timeout) → `pg-monitor <env>: PROBE FAILED — <first error line>`.

Do not investigate, do not run extra queries, do not editorialize. This skill exists
to be cheap; escalation is someone else's job.

## Scheduling it

Inside a session (self-managing loop):

```
/loop 30m /pg-monitor dev
```

Headless from OS cron (survives outside any session):

```cron
*/30 * * * * claude -p "/pg-monitor dev" >> "$HOME/.claude/pg-monitor.log" 2>&1
```

Or create a scheduled task/routine with `/pg-monitor dev` as the prompt — the model
and effort pins in this skill's frontmatter apply wherever it runs, so every firing
costs Haiku-at-low, never your session model.
