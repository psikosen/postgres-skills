---
version: 1.5.0
description: Run the pg-reviewer agent on the current diff (or given files) — BLOCKER/ADVISORY findings for migrations and data-access code before an MR.
argument-hint: "[files or MR ref, defaults to working-tree diff]"
---

Launch the **pg-reviewer** agent (Agent tool, read-only) on: $ARGUMENTS

If no arguments were given, review the current working-tree diff (`git diff` plus
`git diff --staged`), focusing on `*.sql` migration files and any changed data-access
code. Pass the agent the file list and the diff.

When it returns, relay the verdict and findings verbatim — BLOCKERs first with
file:line and the failure scenario. If there are BLOCKERs, offer to fix them; do not
fix silently.
