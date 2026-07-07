---
name: pg-toolkit
version: 1.5.0
description: Maintain the Postgres toolkit itself — check installed-vs-repo drift, upgrade, and make skill/agent changes through the sanctioned flow (repo edit → bump.sh → commit/MR → reinstall). The ONLY correct way to modify pg-* skills.
when_to_use: Use when the user wants to update, improve, version-bump, or check the pg-* skills/agents ("update the toolkit", "am I on the latest pg skills", "change pg-explain to also..."), or when any session is about to edit a file under ~/.claude/skills/pg-* (stop — route here instead).
argument-hint: "[check | upgrade | change <skill> <what>]"
---

# pg-toolkit — maintain the toolkit through the flow, not around it

Live state at load time (repo resolved from PG_TOOLKIT_REPO):
!`bash -c 'source ~/.claude/pg.env 2>/dev/null; R="${PG_TOOLKIT_REPO:-}"; if [ -x "$R/install.sh" ] && [ -f "$R/VERSION" ]; then "$R/install.sh" --check 2>/dev/null; elif [ -x "$R/Postgres/install.sh" ]; then "$R/Postgres/install.sh" --check 2>/dev/null; else echo "PG_TOOLKIT_REPO not configured in ~/.claude/pg.env"; fi; true'`

The repo is the source of truth; `~/.claude/skills/pg-*` are stamped MANAGED copies.
Resolve the repo first: `$PG_TOOLKIT_REPO` from `~/.claude/pg.env` (source it; the path may be the toolkit itself or a parent containing `Postgres/`), else ask
the user where their `claude-code-setup-guide` clone lives — never guess.

## check — "am I current?"

```bash
cd "$PG_TOOLKIT_REPO"/Postgres 2>/dev/null || cd "$PG_TOOLKIT_REPO" && git pull --ff-only && ./install.sh --check
```

Report each unit's state. `OUTDATED` → offer upgrade. `DRIFTED` → show the diff of the
installed copy vs repo and ask: port the local edit into the repo (below), or discard it.

## upgrade

```bash
cd "$PG_TOOLKIT_REPO"/Postgres 2>/dev/null || cd "$PG_TOOLKIT_REPO" && git pull --ff-only && ./install.sh
```

Then remind the user: new/changed skills load in NEW sessions.

## change a skill or agent

1. Edit the file **in the repo** (`Postgres/skills/<name>/…` or `Postgres/agents/…`) —
   never under `~/.claude/`.
2. Keep frontmatter discipline: `description`/`when_to_use` say *when*, the body says
   *how*; scripts stay under `scripts/` and are referenced via `${CLAUDE_SKILL_DIR}`.
3. Version: `./bump.sh <next-semver>` — patch for wording, minor for new
   rules/capabilities, major for breaking script-interface changes. Never hand-edit
   version strings (three places; bump.sh syncs them).
4. Sanity: `bash -n` any touched script; if the linter or a wrapper changed, run it
   against a known-good and known-bad input.
5. Branch, commit (explain the *why* — the commit is the changelog), push, open the MR.
6. After merge: `./install.sh` locally, and tell the team to `git pull && ./install.sh`.

## porting a DRIFTED edit

Copy the local change from the installed file into the repo file, then follow "change a
skill" from step 3. Then reinstall so the stamp matches again.
