# Postgres toolkit for Claude Code

A set of skills, agents, and commands that make Claude handle Postgres work the way a
careful DBA would. Reads go through a guarded wrapper, schema changes go through
migrations, and performance claims come with EXPLAIN plans attached.

## What you get

Skills (these show up as slash commands, and Claude also picks them up on its own):

- `/pg-query <env> "<sql>"` — ad-hoc read-only queries. The wrapper forces a read-only
  session and a statement timeout, so nobody fat-fingers an UPDATE into beta.
- `/pg-explain <env> "<sql>"` — EXPLAIN (ANALYZE, BUFFERS) inside a transaction that
  rolls back, so you can safely analyze writes too. Comes with instructions that teach
  Claude to actually read the plan instead of guessing.
- `/pg-migration <what you want>` — writes migration scripts the safe way and lints
  them for the stuff that causes real incidents: DELETE without WHERE, CONCURRENTLY
  inside a transaction, index builds that blow the deploy timeout.
- `/pg-health <env>` — one-shot health report: sizes, seq-scan hot spots, unused
  indexes, connection counts, vacuum lag, top queries.
- `/pg-toolkit` — maintains the toolkit itself. Checks whether your copies are stale,
  upgrades them, and walks skill changes through the release flow.

Agents (Claude launches these for bigger jobs; all read-only):

- `pg-reviewer` — reviews migrations and data-access code before an MR. Findings come
  back as BLOCKER or ADVISORY with file and line.
- `pg-perf` — takes "this endpoint is slow" and comes back with the actual query, the
  plan, and a ranked fix list.
- `pg-triage` — for when the database is on fire right now. Finds the lock chain or
  the runaway query and hands you the kill commands to run yourself. It never runs
  them for you.
- `pg-detective` — figures out how bad data got that way. Walks foreign keys, audit
  tables, and the code that writes the table, then tells you the story with a blast
  radius count.
- `pg-ponytail` — the lazy-senior-DBA pass. Reads SQL Claude just wrote and flags
  over-engineering only: reinvented Postgres features, speculative columns and
  indexes, trigger machinery where a constraint would do. Tells you what to delete.

Commands (shortcuts that point the agents at something):

- `/pg-review` — pg-reviewer on your current diff.
- `/pg-perf <env> <symptom>` — kick off a performance investigation.
- `/pg-triage <env> <what's happening>` — kick off incident triage.
- `/pg-ponytail` — over-engineering review of the SQL in your current diff. Run it
  next to `/pg-review`: one hunts complexity, the other hunts bugs.

## Setup

```bash
./install.sh
cp ~/.claude/pg.env.example ~/.claude/pg.env
chmod 600 ~/.claude/pg.env
```

Then open `~/.claude/pg.env` and define your environments, one shell function per
environment. Static credentials work for a local DB; for shared environments the
example shows how to pull the connection string from Azure Key Vault on demand, so
nothing sensitive sits in the file. Set `PG_TOOLKIT_REPO` in there too so `/pg-toolkit`
knows where this repo lives.

Start a new Claude Code session and the skills are live. You need `psql` on your PATH,
and a logged-in `az` CLI if your environments fetch from Key Vault.

## How updates work

The repo is the source of truth. `install.sh` copies files into `~/.claude/`, and those
copies just sit there until you refresh them:

```bash
git pull && ./install.sh     # get current
./install.sh --check         # am I current? (OK / OUTDATED / DRIFTED per item)
./install.sh --uninstall     # remove everything it installed
```

Installed files carry a MANAGED stamp telling you (and any Claude session) to make
changes in the repo rather than in `~/.claude/` directly. `--check` catches it if
someone does anyway: OUTDATED means the repo moved on and you should reinstall,
DRIFTED means your local copy has edits that the next install will erase — port them
into the repo or let them go.

The installer also wires up three hooks in `~/.claude/settings.json` (it merges them
in without touching your existing entries, and `--uninstall` takes them back out):

- Pre-tool guard: any Bash command that calls raw `psql` outside the toolkit wrappers
  gets held for your approval instead of running silently. Export
  `PG_ALLOW_RAW_PSQL=1` to turn the guard off.
- Post-edit lint: the moment a migration file gets written or edited, the linter runs.
  BLOCKERs bounce straight back to Claude to fix; warnings show up as context.
- Session start: runs the drift check and prints a one-liner when your copies are
  OUTDATED or DRIFTED. Quiet when everything is current.

## Changing the toolkit

Edit in the repo, bump, ship:

```bash
# edit skills/pg-explain/SKILL.md (or whatever)
./bump.sh 1.2.0      # updates VERSION, every frontmatter, and the fragment marker
git commit -am "pg-explain: <what and why>"
# open a PR; after merge everyone runs: git pull && ./install.sh
```

`bump.sh` is the only sanctioned way to change version numbers — it keeps the three
places they appear in sync, and `install.sh` refuses to install a half-bumped release.
Git holds the whole history: `git log skills/pg-explain/` is the changelog, `git blame`
answers who and when, and a bad release is a revert plus a reinstall.

## Why the CLAUDE.md fragment is so small

Anything in your global CLAUDE.md costs tokens in every single session. So the fragment
carries only the rules that must always be on — no raw psql against shared DBs, schema
changes through migrations only, no perf claims without a plan — and everything
procedural lives in the skills, which load only when used.

## A note on safety

The wrappers enforce read-only and timeouts at the session level (`PGOPTIONS`), so
protection comes from the mechanism rather than from Claude remembering an
instruction. It's a guardrail, not a jail: the point is to make the safe path the
easy path.
