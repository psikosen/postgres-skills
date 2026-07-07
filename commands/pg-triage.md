---
version: 1.4.0
description: Run the pg-triage agent — live-incident diagnosis (locks, connection exhaustion, runaway queries) with copy-pastable remediation commands for a human to execute.
argument-hint: "[env] [what's happening]"
---

Launch the **pg-triage** agent (Agent tool, read-only) with: $ARGUMENTS

Give it the environment and the symptom as reported. It diagnoses through the
read-only wrapper only.

Relay its verdict, the blocking chain, and the remediation commands exactly as
written, in its least-to-most-destructive order. Do not execute any remediation
command yourself — pg_cancel/pg_terminate and setting changes are the user's call
and the user's keyboard.
