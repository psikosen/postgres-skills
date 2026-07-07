#!/usr/bin/env bash
# Postgres toolkit — Installer
#
#   ./install.sh              install or upgrade
#   ./install.sh --uninstall  remove everything it installed
#
# What it does:
#   * Copies skill DIRECTORIES (SKILL.md + scripts/) into ~/.claude/skills/
#     and the pg-reviewer agent into ~/.claude/agents/ (chmod +x on scripts).
#   * Appends the CLAUDE.md fragment to ~/.claude/CLAUDE.md between versioned
#     markers. On upgrade the block is REPLACED in place, so installed copies
#     can't drift from the repo (backup taken first either way).
#   * Ships pg.env.example to ~/.claude/ — never touches a real ~/.claude/pg.env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
TARGET="$CLAUDE_DIR/CLAUDE.md"
FRAGMENT="$SCRIPT_DIR/CLAUDE.md.fragment"
TS="$(date +%Y%m%d-%H%M%S)"

# Markers: match on the stable prefix so version bumps still count as "present".
BEGIN_PREFIX="# --- Postgres toolkit (optional add-on)"
END_MARKER="# --- end Postgres toolkit block ---"

SKILLS=(pg-query pg-explain pg-migration pg-health pg-toolkit)
AGENTS=(pg-reviewer.md)

# ---------------------------------------------------------------------------
# Managed-copy machinery: installed files are stamped so (a) humans and Claude
# sessions know edits belong in the repo, and (b) --check can tell OUTDATED
# (repo moved on) apart from DRIFTED (someone edited the installed copy).
# ---------------------------------------------------------------------------
MANAGED_NOTE="MANAGED by Postgres/install.sh"

stamp_md() { # insert an HTML comment right after the YAML frontmatter
  local f="$1" ver="$2"
  local note="<!-- $MANAGED_NOTE v$ver — edit in the repo (Postgres/), not here; local edits are overwritten on install. -->"
  awk -v note="$note" '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm == 1 && $0 == "---" { print; print note; fm = 2; next }
    { print }
  ' "$f" > "$f.tmp"
  grep -qF "$MANAGED_NOTE" "$f.tmp" || { printf '%s\n' "$note" | cat - "$f" > "$f.tmp"; }
  mv "$f.tmp" "$f"
}

stamp_sh() { # insert a comment right after the shebang
  local f="$1" ver="$2"
  local note="# $MANAGED_NOTE v$ver — edit in the repo (Postgres/), not here; local edits are overwritten on install."
  awk -v note="$note" 'NR == 1 { print; print note; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

installed_version_of() { # read the stamped version out of an installed file
  grep -m1 -oE "$MANAGED_NOTE v[0-9]+\.[0-9]+\.[0-9]+" "$1" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true
}

check_unit() { # $1 = label, $2 = repo path (file or dir), $3 = installed path
  local label="$1" repo="$2" inst="$3"
  local status="OK" iver="" drift_files=()

  if [[ ! -e "$inst" ]]; then
    printf '  %-14s NOT INSTALLED\n' "$label"
    return 1
  fi

  while IFS= read -r rf; do
    local rel="${rf#"$repo"/}"; [[ "$rf" == "$repo" ]] && rel="$(basename "$rf")"
    local inf="$inst/$rel"; [[ -f "$inst" ]] && inf="$inst"
    if [[ ! -f "$inf" ]]; then drift_files+=("$rel (missing)"); continue; fi
    [[ -z "$iver" ]] && iver="$(installed_version_of "$inf")"
    if ! diff -q <(grep -vF "$MANAGED_NOTE" "$inf") "$rf" >/dev/null; then
      drift_files+=("$rel")
    fi
  done < <(find "$repo" -type f \( -name '*.md' -o -name '*.sh' \) | sort)

  local repo_ver; repo_ver="$(cat "$SCRIPT_DIR/VERSION")"
  if [[ ${#drift_files[@]} -gt 0 ]]; then
    if [[ -n "$iver" && "$iver" != "$repo_ver" ]]; then
      printf '  %-14s OUTDATED   (installed v%s, repo v%s — re-run ./install.sh)\n' "$label" "${iver:-?}" "$repo_ver"
    else
      printf '  %-14s DRIFTED    (installed copy has local edits — LOST on reinstall)\n' "$label"
      for d in "${drift_files[@]}"; do printf '                   diff: %s\n' "$d"; done
    fi
    return 1
  fi
  printf '  %-14s OK         (matches repo v%s)\n' "$label" "$repo_ver"
}

if [[ "${1:-}" == "--check" ]]; then
  echo "=== Postgres toolkit — drift check (repo v$(cat "$SCRIPT_DIR/VERSION")) ==="
  rc=0
  for s in "${SKILLS[@]}"; do
    check_unit "$s" "$SCRIPT_DIR/skills/$s" "$CLAUDE_DIR/skills/$s" || rc=1
  done
  for a in "${AGENTS[@]}"; do
    check_unit "${a%.md}" "$SCRIPT_DIR/agents/$a" "$CLAUDE_DIR/agents/$a" || rc=1
  done
  exit $rc
fi

remove_block() { # strip the marker-delimited block from CLAUDE.md, in place
  awk -v begin="$BEGIN_PREFIX" -v end="$END_MARKER" '
    index($0, begin) == 1 { skipping = 1; next }
    skipping && $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "=== Postgres toolkit — Uninstall ==="
  for s in "${SKILLS[@]}"; do
    rm -rf "$CLAUDE_DIR/skills/$s" && echo "  removed skills/$s"
  done
  for a in "${AGENTS[@]}"; do
    rm -f "$CLAUDE_DIR/agents/$a" && echo "  removed agents/$a"
  done
  if [[ -f "$TARGET" ]] && grep -qF "$BEGIN_PREFIX" "$TARGET"; then
    cp "$TARGET" "$TARGET.pre-pg-uninstall.$TS"
    remove_block
    echo "  removed Postgres block from ~/.claude/CLAUDE.md (backup: CLAUDE.md.pre-pg-uninstall.$TS)"
  fi
  echo "Left in place: ~/.claude/pg.env (your credentials registry, if you created one)."
  exit 0
fi

VERSION="$(cat "$SCRIPT_DIR/VERSION")"

echo "=== Postgres toolkit — Installer (v$VERSION) ==="
echo "Source:      $SCRIPT_DIR"
echo "Destination: $CLAUDE_DIR"
echo ""

# Version-consistency guard: the fragment marker and VERSION must agree
# (both are maintained via ./bump.sh). Refuse to install a half-bumped release.
if ! head -1 "$FRAGMENT" | grep -qF "v$VERSION"; then
  echo "ERROR: CLAUDE.md.fragment marker version does not match VERSION ($VERSION)." >&2
  echo "       Run ./bump.sh $VERSION to sync, then re-run install." >&2
  exit 1
fi

# Report what's currently installed (the marker in the user's CLAUDE.md).
if [[ -f "$TARGET" ]]; then
  installed_line="$(grep -m1 "^$BEGIN_PREFIX" "$TARGET" || true)"
  if [[ -n "$installed_line" ]]; then
    echo "Currently installed: ${installed_line#"$BEGIN_PREFIX" }"
    echo "This run installs:   v$VERSION ---"
    echo ""
  fi
fi

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"

echo "Installing skills (directory + scripts)..."
for s in "${SKILLS[@]}"; do
  if [[ -d "$CLAUDE_DIR/skills/$s" ]]; then echo "  [UPDATE] skills/$s"; else echo "  [NEW]    skills/$s"; fi
  rm -rf "$CLAUDE_DIR/skills/$s"
  cp -R "$SCRIPT_DIR/skills/$s" "$CLAUDE_DIR/skills/$s"
  stamp_md "$CLAUDE_DIR/skills/$s/SKILL.md" "$VERSION"
  while IFS= read -r sh; do stamp_sh "$sh" "$VERSION"; chmod +x "$sh"; done \
    < <(find "$CLAUDE_DIR/skills/$s" -name '*.sh' -type f)
done

echo "Installing agents..."
for a in "${AGENTS[@]}"; do
  if [[ -f "$CLAUDE_DIR/agents/$a" ]]; then echo "  [UPDATE] agents/$a"; else echo "  [NEW]    agents/$a"; fi
  cp "$SCRIPT_DIR/agents/$a" "$CLAUDE_DIR/agents/$a"
  stamp_md "$CLAUDE_DIR/agents/$a" "$VERSION"
done

echo "Shipping pg.env.example..."
cp "$SCRIPT_DIR/pg.env.example" "$CLAUDE_DIR/pg.env.example"
if [[ ! -f "$CLAUDE_DIR/pg.env" ]]; then
  echo "  NOTE: no ~/.claude/pg.env yet — copy pg.env.example to pg.env, add your"
  echo "        environments, and chmod 600 it. The skills refuse to run without it."
fi

echo ""
if [[ ! -f "$TARGET" ]]; then
  echo "No ~/.claude/CLAUDE.md found — creating it from the fragment."
  cp "$FRAGMENT" "$TARGET"
elif grep -qF "$BEGIN_PREFIX" "$TARGET"; then
  echo "Postgres block already present — replacing in place (upgrade)."
  cp "$TARGET" "$TARGET.pre-pg.$TS"
  remove_block
  printf '\n' >> "$TARGET"
  cat "$FRAGMENT" >> "$TARGET"
  echo "  (backup: CLAUDE.md.pre-pg.$TS)"
else
  echo "Appending Postgres block to ~/.claude/CLAUDE.md."
  cp "$TARGET" "$TARGET.pre-pg.$TS"
  printf '\n' >> "$TARGET"
  cat "$FRAGMENT" >> "$TARGET"
  echo "  (backup: CLAUDE.md.pre-pg.$TS)"
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Try it (after configuring ~/.claude/pg.env):"
echo "  /pg-query dev \"select count(*) from users\""
echo "  /pg-explain dev \"select ...\""
echo "  /pg-health dev"
echo "  /pg-migration add an index on ..."
echo ""
echo "Uninstall: ./install.sh --uninstall"
