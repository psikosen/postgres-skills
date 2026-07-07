#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — intercepts raw psql invocations.
# The toolkit's rule is that database reads go through the guarded wrappers
# (read-only session + statement timeout). This makes the rule mechanical:
# a Bash command that calls psql directly, outside the toolkit's own scripts,
# gets flagged for explicit user approval instead of running silently.
#
# Escape hatch: export PG_ALLOW_RAW_PSQL=1 in your shell to disable the guard.
set -euo pipefail

[[ "${PG_ALLOW_RAW_PSQL:-0}" == "1" ]] && exit 0

# NB: capture the hook's stdin BEFORE python — `python3 -` reads the PROGRAM
# from stdin, so the JSON payload must travel via argv instead.
INPUT="$(cat)"

python3 - "$INPUT" <<'PY'
import json, re, sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

cmd = (data.get("tool_input") or {}).get("command") or ""

# Only care about commands that actually invoke psql as a program.
if not re.search(r'(^|[\s;|&(])psql(\s|$)', cmd):
    sys.exit(0)

# The toolkit's own wrappers are the sanctioned path.
if "/skills/pg-" in cmd or "psql-ro.sh" in cmd or "explain.sh" in cmd or "health.sh" in cmd:
    sys.exit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": (
            "Raw psql call detected. Toolkit rule: reads go through /pg-query "
            "(psql-ro.sh — read-only session + timeout), plans through /pg-explain. "
            "Approve only if this genuinely needs raw psql (e.g. a sanctioned write "
            "the user already confirmed). Set PG_ALLOW_RAW_PSQL=1 to disable this guard."
        ),
    }
}))
PY
