---
version: 1.4.0
description: Run the pg-perf agent — full performance investigation of a slow query, endpoint, or general slowness report, with EXPLAIN evidence and a ranked fix list.
argument-hint: "[env] [query, endpoint, or symptom]"
---

Launch the **pg-perf** agent (Agent tool, read-only) with: $ARGUMENTS

Give it the target environment, the query/endpoint/symptom, and repo paths to the
relevant data-access code if known. Remind it to use the toolkit wrappers
(`psql-ro.sh`, `explain.sh`) for every database touch.

Relay its diagnosis and ranked fixes. Route any MIGRATION-tagged fix to /pg-migration
before implementing; QUICK fixes need the user's go-ahead like any other change.
