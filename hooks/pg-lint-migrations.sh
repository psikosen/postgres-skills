#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write|MultiEdit) — auto-lints migration files.
# The moment a ScriptNNNN_*.sql (or anything under Scripts/ or migrations/) is
# written or edited, the toolkit's migration linter runs. BLOCKER findings are
# fed back to Claude as a block so they get fixed before the file is committed;
# warnings surface as plain context.
set -euo pipefail

LINTER="$HOME/.claude/skills/pg-migration/scripts/lint-migration.sh"
[[ -x "$LINTER" ]] || exit 0

# NB: capture the hook's stdin BEFORE python — `python3 -` reads the PROGRAM
# from stdin, so the JSON payload must travel via argv instead.
INPUT="$(cat)"

python3 - "$LINTER" "$INPUT" <<'PY'
import json, re, subprocess, sys

linter = sys.argv[1]
try:
    data = json.loads(sys.argv[2])
except Exception:
    sys.exit(0)

path = (data.get("tool_input") or {}).get("file_path") or ""
if not path.endswith(".sql"):
    sys.exit(0)
if not (re.search(r"Script\d+_.*\.sql$", path)
        or "/Scripts/" in path
        or "/migrations/" in path.lower()):
    sys.exit(0)

proc = subprocess.run([linter, path], capture_output=True, text=True)
output = (proc.stdout + proc.stderr).strip()

if proc.returncode == 1:
    # BLOCKERs: bounce it back so the model fixes the script before moving on.
    print(json.dumps({
        "decision": "block",
        "reason": "Migration linter found BLOCKERs in " + path + ":\n" + output
                  + "\nFix these before continuing (see /pg-migration).",
    }))
elif "  warning:" in output:
    # Warnings only: surface as context, don't interrupt.
    print("Migration linter (" + path + "):\n" + output)
PY
