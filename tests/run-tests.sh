#!/usr/bin/env bash
# run-tests.sh — the toolkit's whole verification suite in one command.
# Runs locally and in CI identically. No database, no secrets, no network.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
say()  { printf '%s\n' "$*"; }
pass() { say "  ok: $*"; }
flunk(){ say "  FAIL: $*"; fail=1; }

say "== 1. every script parses =="
for f in install.sh bump.sh skills/*/scripts/*.sh hooks/*.sh; do
  bash -n "$f" && pass "$f" || flunk "$f"
done

say "== 2. version consistency (VERSION == fragment marker == every frontmatter) =="
VER="$(cat VERSION)"
head -1 CLAUDE.md.fragment | grep -qF "v$VER" && pass "fragment marker v$VER" || flunk "fragment marker != $VER"
while IFS=: read -r file line; do
  [[ "$line" == "version: $VER" ]] && pass "$file" || flunk "$file has '$line', want 'version: $VER'"
done < <(grep -H "^version:" skills/*/SKILL.md agents/*.md commands/*.md)

say "== 3. migration linter behavior =="
if ./skills/pg-migration/scripts/lint-migration.sh tests/fixture-bad-migration.sql >/dev/null 2>&1; then
  flunk "bad fixture passed the linter"
else
  pass "bad fixture rejected (exit 1)"
fi
./skills/pg-migration/scripts/lint-migration.sh tests/fixture-good-migration.sql >/dev/null 2>&1 \
  && pass "good fixture accepted" || flunk "good fixture rejected"

say "== 4. hook payload behavior =="
out="$(echo '{"tool_name":"Bash","tool_input":{"command":"psql -h db -c \"select 1\""}}' | ./hooks/pg-guard-raw-psql.sh)"
[[ "$out" == *'"permissionDecision": "ask"'* ]] && pass "guard asks on raw psql" || flunk "guard did not ask: $out"
out="$(echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | ./hooks/pg-guard-raw-psql.sh)"
[[ -z "$out" ]] && pass "guard silent on unrelated command" || flunk "guard spoke up on git status"
out="$(echo '{"tool_name":"Bash","tool_input":{"command":"psql -c 1"}}' | PG_ALLOW_RAW_PSQL=1 ./hooks/pg-guard-raw-psql.sh)"
[[ -z "$out" ]] && pass "guard escape hatch" || flunk "escape hatch ignored"

say "== 5. install lifecycle in a sandbox HOME =="
SB="$(mktemp -d)"
mkdir -p "$SB/.claude"
printf '# user rules\nkeep me\n' > "$SB/.claude/CLAUDE.md"
printf '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo mine"}]}]}}\n' > "$SB/.claude/settings.json"
HOME="$SB" ./install.sh >/dev/null 2>&1               && pass "install" || flunk "install"
HOME="$SB" ./install.sh --check >/dev/null 2>&1        && pass "--check all OK after install" || flunk "--check dirty after install"
HOME="$SB" ./install.sh >/dev/null 2>&1
[[ "$(grep -c '^# --- Postgres toolkit' "$SB/.claude/CLAUDE.md")" == "1" ]] \
  && pass "reinstall keeps exactly one fragment block" || flunk "fragment duplicated"
[[ "$(grep -c 'hooks/pg-' "$SB/.claude/settings.json")" == "3" ]] \
  && pass "reinstall keeps exactly three hook entries" || flunk "hook entries duplicated"
echo "tamper" >> "$SB/.claude/skills/pg-query/SKILL.md"
# capture first: --check exits 1 on drift, which under pipefail would mask grep
check_out="$(HOME="$SB" ./install.sh --check 2>/dev/null || true)"
if grep -q "pg-query.*DRIFTED" <<<"$check_out"; then
  pass "--check detects drift"
else
  flunk "--check missed drift: $check_out"
fi
HOME="$SB" ./install.sh --uninstall >/dev/null 2>&1    && pass "uninstall" || flunk "uninstall"
grep -q "keep me" "$SB/.claude/CLAUDE.md"              && pass "user CLAUDE.md content survives" || flunk "user content lost"
! grep -q "Postgres toolkit" "$SB/.claude/CLAUDE.md"   && pass "fragment removed" || flunk "fragment left behind"
grep -q "echo mine" "$SB/.claude/settings.json"        && pass "user hooks survive uninstall" || flunk "user hooks lost"
! grep -q "hooks/pg-" "$SB/.claude/settings.json"      && pass "pg hook entries removed" || flunk "pg hooks left behind"
rm -rf "$SB"

say ""
if [[ $fail -eq 0 ]]; then say "ALL TESTS PASSED"; else say "TESTS FAILED"; exit 1; fi
