# Postgres toolkit

Guarded SQL/Postgres workflows for Claude Code: read-only querying, EXPLAIN-driven
performance work, migration authoring with lint guardrails, instance health triage,
and a read-only SQL reviewer agent.

## What's inside

| Piece | Invoke | What it does |
|---|---|---|
| `skills/pg-query` | `/pg-query <env> "<sql>"` | Ad-hoc **read-only** queries via `scripts/psql-ro.sh` (read-only session, statement timeout) |
| `skills/pg-explain` | `/pg-explain <env> "<sql>"` | `EXPLAIN (ANALYZE, BUFFERS)` inside BEGIN…ROLLBACK via `scripts/explain.sh`, plus plan-reading discipline |
| `skills/pg-migration` | `/pg-migration ...` | Migration authoring checklist + `scripts/lint-migration.sh` (BLOCKER/warning static lint) |
| `skills/pg-health` | `/pg-health <env>` | Full health snapshot via `scripts/health.sh`, summarized into ranked findings (runs forked) |
| `agents/pg-reviewer` | via Agent tool | Read-only BLOCKER/ADVISORY review of migrations and data-access code |
| `CLAUDE.md.fragment` | always resident | ~20 lines: the safety rules + routing, nothing else |

## Install / upgrade / uninstall

```bash
cd Postgres
./install.sh              # install, or upgrade in place
./install.sh --uninstall  # remove skills, agent, and the CLAUDE.md block
```

Then configure your environments once:

```bash
cp ~/.claude/pg.env.example ~/.claude/pg.env
chmod 600 ~/.claude/pg.env
# edit: one pg_env_<name>() function per environment (static creds or fetched
# on demand — a Key Vault example is included). Never commit this file.
```

## Design notes (why it's shaped this way)

- **The fragment is deliberately tiny.** CLAUDE.md content is a per-session token tax,
  so it carries only what must be *always on*: the never-raw-psql / migrations-only /
  no-perf-claims-without-EXPLAIN rules and two routing hints. Every procedure lives in
  a skill, which loads only when used.
- **Skills are directories, not flat files.** Each bundles its `scripts/*.sh` and
  references them via `${CLAUDE_SKILL_DIR}`, so they work regardless of the working
  directory. `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/x.sh *)` pre-approves
  exactly the bundled script and nothing else (needs Claude Code ≥ 2.1.196 for the
  substitution in allowed-tools).
- **Scripts are the guardrail, prose is the policy.** The wrappers enforce read-only +
  timeouts mechanically (`PGOPTIONS`), so safety doesn't depend on the model
  remembering an instruction. The fragment's rules exist so Claude *routes* to the
  wrappers.
- **Versioned, replaceable block.** The fragment's begin marker carries a version and
  `install.sh` replaces the block in place on re-run — installed copies can't silently
  drift from the repo (the classic failure of append-only fragment installers).
- **No `commands/` folder.** Custom commands were merged into skills; a skill directory
  gives the same `/name` invocation plus bundled files and frontmatter control.

## Versioning

The toolkit is versioned in three visible places — `VERSION`, every `SKILL.md`/agent
frontmatter `version:`, and the `CLAUDE.md.fragment` begin-marker — kept in sync by one
command:

```bash
./bump.sh 1.1.0   # updates all three; hand-editing any one of them is how drift starts
```

`install.sh` refuses to run a half-bumped release (fragment marker ≠ `VERSION`), and on
upgrade prints the installed vs incoming version before replacing the block in place.
So "what version does this teammate have?" is answered by the marker line in their
`~/.claude/CLAUDE.md` and the `version:` in any installed `SKILL.md`.

Release flow: change files → `./bump.sh X.Y.Z` → commit/MR → teammates `git pull` and
re-run `./install.sh`.

**Managed copies + drift detection.** Installed files are stamped with a
`MANAGED by Postgres/install.sh vX.Y.Z` header (after the frontmatter / shebang, so
nothing breaks) telling humans and Claude sessions alike that edits belong in the repo.
`./install.sh --check` then diffs every installed file against the repo and reports,
per skill/agent:

- `OK` — matches the repo at the current version.
- `OUTDATED` — the repo released a newer version; re-run `./install.sh`.
- `DRIFTED` — the installed copy was edited in place; those edits are LOST on the next
  install. Either port them into the repo (MR + `bump.sh`) or let the reinstall erase
  them. Nonzero exit code, so it's automatable (shell profile, session-start hook, CI).

> **When to graduate to a plugin:** Claude Code plugins carry a `plugin.json` version
> and update through marketplaces — no installer script, no fragment. If this toolkit
> stabilizes and the team wants push-button updates, converting it (skills/ and agents/
> move over nearly as-is) is the natural next step; the CLAUDE.md fragment content
> would become the plugin's memory file.

**Automatic drift nagging (optional).** Skills only run when invoked — for a check that
happens *without asking*, add a SessionStart hook to `~/.claude/settings.json` (set
`PG_TOOLKIT_REPO` in `~/.claude/pg.env` first):

```json
{ "hooks": { "SessionStart": [ { "matcher": "startup", "hooks": [
  { "type": "command", "timeout": 15,
    "command": "bash -c 'source ~/.claude/pg.env 2>/dev/null; [ -d \"$PG_TOOLKIT_REPO/Postgres\" ] && \"$PG_TOOLKIT_REPO/Postgres/install.sh\" --check 2>/dev/null | grep -E \"OUTDATED|DRIFTED\" || true'" }
] } ] } }
```

Every new session then starts with a one-line warning if your copies are stale or
edited — and stays silent when everything is OK.

## Credentials

The scripts never store credentials. `~/.claude/pg.env` defines `pg_env_<name>()`
functions that export the standard `PG*` variables — statically for local DBs, or
fetched on demand (Key Vault, Vault, SSM...) for shared ones. `PG_TIMEOUT_MS`
overrides per-script timeouts when a legitimately heavy read needs it.
