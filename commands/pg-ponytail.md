---
version: 1.4.0
description: Run the pg-ponytail agent — over-engineering-only review of SQL just written (usually by Claude). Finds reinvented Postgres features, speculative schema, and one-line replacements. Pair with /pg-review, which covers correctness.
argument-hint: "[files, defaults to *.sql in the working-tree diff]"
---

Launch the **pg-ponytail** agent (Agent tool, read-only) on: $ARGUMENTS

If no arguments were given, target the SQL in the current working-tree diff
(`git diff` plus `git diff --staged`, filtered to `*.sql` and files containing SQL
strings that changed). Tell the agent which of those changes were just authored in
this session, since freshly generated SQL is its main audience.

Relay findings verbatim — one line each, cuts first. If the agent recommends
deletions, offer to apply them; apply nothing silently. For a full pre-MR pass run
/pg-review as well: ponytail hunts complexity, pg-reviewer hunts bugs, and a diff
needs to survive both.
