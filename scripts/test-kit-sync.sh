#!/usr/bin/env bash
# Synthetic test for mr-kit-sync.
#
# Builds two scenarios in /tmp:
#   A) Clean upgrade: v0.1.0 project, no local edits → sync to v0.2.0 → file gets new paragraph.
#   B) Conflict: v0.1.0 project, local edit on the SAME file upstream edits → sync emits conflict markers.
#
# Exits 0 on success, 1 on any failure.
#
# This is a STAND-ALONE test of the merge logic (not a full workflow run). It extracts the
# core 3-way merge bash from .archon/workflows/mr-kit-sync.yaml and runs it directly.
set -e

WORKDIR=$(mktemp -d -t kit-sync-test-XXXXXX)
echo "Test workdir: $WORKDIR"
trap "rm -rf $WORKDIR" EXIT

KIT="$WORKDIR/kit"
PROJ_A="$WORKDIR/proj-clean"
PROJ_B="$WORKDIR/proj-conflict"

# Setup a synthetic kit repo with two tags ----------------------------------
mkdir -p "$KIT"
cd "$KIT"
git init -q -b main
git config user.email test@test
git config user.name test
mkdir -p .archon .claude/skills/sample
echo "0.1.0" > .archon/KIT_VERSION
cat > MR-Archon.md <<'EOF'
# MR-Archon — kit manual

Section A.

Section B.
EOF
cat > .claude/skills/sample/SKILL.md <<'EOF'
---
name: sample
description: A sample skill.
---

# Sample skill body v1.
EOF
git add -A
git commit -q -m "v0.1.0"
git tag v0.1.0

# Bump to v0.2.0 — add a paragraph to MR-Archon.md, edit the SKILL.md
cat > MR-Archon.md <<'EOF'
# MR-Archon — kit manual

Section A.

Section B.

Section C — added in v0.2.0.
EOF
cat > .claude/skills/sample/SKILL.md <<'EOF'
---
name: sample
description: A sample skill.
---

# Sample skill body v2 — improved.
EOF
echo "0.2.0" > .archon/KIT_VERSION
git add -A
git commit -q -m "v0.2.0"
git tag v0.2.0

# Scenario A: clean upgrade -------------------------------------------------
echo ""
echo "=== Scenario A: clean upgrade (no local edits) ==="
git clone -q "$KIT" "$PROJ_A"
cd "$PROJ_A"
git config user.email test@test
git config user.name test
git checkout -q v0.1.0
git branch -D main 2>/dev/null || true
git checkout -qb main
echo "0.1.0" > .archon/KIT_VERSION  # Pretend project tracks 0.1.0
git add -A
git commit -q -m "Pretend bootstrap state at 0.1.0" --allow-empty

git remote rename origin kit 2>/dev/null || git remote add kit "$KIT"
git fetch -q kit --tags

# --- Run the merge logic (extracted from mr-kit-sync.yaml three-way-merge node) ---
FROM=$(cat .archon/KIT_VERSION)
TO=0.2.0
BASE_REF="v$FROM"
TARGET_REF="v$TO"

KIT_PATHS=(".archon" ".claude/skills" "MR-Archon.md")

CONFLICTED=0
for prefix in "${KIT_PATHS[@]}"; do
  TARGET_FILES=$(git ls-tree -r --name-only "$TARGET_REF" -- "$prefix" 2>/dev/null || true)
  BASE_FILES=$(git ls-tree -r --name-only "$BASE_REF" -- "$prefix" 2>/dev/null || true)
  ALL_FILES=$(printf '%s\n%s\n' "$TARGET_FILES" "$BASE_FILES" | sort -u | sed '/^$/d')
  for f in $ALL_FILES; do
    IN_BASE=0; IN_TARGET=0; IN_OURS=0
    git cat-file -e "$BASE_REF:$f" 2>/dev/null && IN_BASE=1 || true
    git cat-file -e "$TARGET_REF:$f" 2>/dev/null && IN_TARGET=1 || true
    [ -f "$f" ] && IN_OURS=1 || true
    if [ "$IN_BASE" = "1" ] && [ "$IN_TARGET" = "1" ] && [ "$IN_OURS" = "1" ]; then
      BASE_FILE=$(mktemp); git cat-file blob "$BASE_REF:$f" > "$BASE_FILE"
      OURS_FILE=$(mktemp); cp "$f" "$OURS_FILE"
      THEIRS_FILE=$(mktemp); git cat-file blob "$TARGET_REF:$f" > "$THEIRS_FILE"
      if cmp -s "$OURS_FILE" "$BASE_FILE"; then
        cp "$THEIRS_FILE" "$f"
      elif git merge-file --diff3 -L "OURS" -L "BASE" -L "THEIRS" "$OURS_FILE" "$BASE_FILE" "$THEIRS_FILE" >/dev/null 2>&1; then
        cp "$OURS_FILE" "$f"
      else
        cp "$OURS_FILE" "$f"
        CONFLICTED=$((CONFLICTED + 1))
        echo "CONFLICT: $f"
      fi
      rm -f "$BASE_FILE" "$OURS_FILE" "$THEIRS_FILE"
    fi
  done
done

if [ "$CONFLICTED" -ne 0 ]; then
  echo "FAIL Scenario A: expected 0 conflicts, got $CONFLICTED"
  exit 1
fi

if grep -q "Section C — added in v0.2.0" MR-Archon.md; then
  echo "PASS Scenario A: v0.2.0 paragraph present"
else
  echo "FAIL Scenario A: v0.2.0 paragraph missing"
  cat MR-Archon.md
  exit 1
fi

# Scenario B: conflict ------------------------------------------------------
echo ""
echo "=== Scenario B: conflict (same line edited locally + upstream) ==="
git clone -q "$KIT" "$PROJ_B"
cd "$PROJ_B"
git config user.email test@test
git config user.name test
git checkout -q v0.1.0
git branch -D main 2>/dev/null || true
git checkout -qb main
echo "0.1.0" > .archon/KIT_VERSION
# Modify the SAME file upstream will modify, on the same trailing line
cat > MR-Archon.md <<'EOF'
# MR-Archon — kit manual

Section A.

Section B.

Section X — local custom paragraph.
EOF
git add -A
git commit -q -m "Local edit to MR-Archon.md" --allow-empty

git remote rename origin kit 2>/dev/null || git remote add kit "$KIT"
git fetch -q kit --tags

# Run merge logic
FROM=$(cat .archon/KIT_VERSION)
TO=0.2.0
BASE_REF="v$FROM"
TARGET_REF="v$TO"

CONFLICTED=0
CONFLICT_FILES=""
for prefix in ".archon" ".claude/skills" "MR-Archon.md"; do
  TARGET_FILES=$(git ls-tree -r --name-only "$TARGET_REF" -- "$prefix" 2>/dev/null || true)
  BASE_FILES=$(git ls-tree -r --name-only "$BASE_REF" -- "$prefix" 2>/dev/null || true)
  ALL_FILES=$(printf '%s\n%s\n' "$TARGET_FILES" "$BASE_FILES" | sort -u | sed '/^$/d')
  for f in $ALL_FILES; do
    IN_BASE=0; IN_TARGET=0; IN_OURS=0
    git cat-file -e "$BASE_REF:$f" 2>/dev/null && IN_BASE=1 || true
    git cat-file -e "$TARGET_REF:$f" 2>/dev/null && IN_TARGET=1 || true
    [ -f "$f" ] && IN_OURS=1 || true
    if [ "$IN_BASE" = "1" ] && [ "$IN_TARGET" = "1" ] && [ "$IN_OURS" = "1" ]; then
      BASE_FILE=$(mktemp); git cat-file blob "$BASE_REF:$f" > "$BASE_FILE"
      OURS_FILE=$(mktemp); cp "$f" "$OURS_FILE"
      THEIRS_FILE=$(mktemp); git cat-file blob "$TARGET_REF:$f" > "$THEIRS_FILE"
      if cmp -s "$OURS_FILE" "$BASE_FILE"; then
        cp "$THEIRS_FILE" "$f"
      elif git merge-file --diff3 -L "OURS" -L "BASE" -L "THEIRS" "$OURS_FILE" "$BASE_FILE" "$THEIRS_FILE" >/dev/null 2>&1; then
        cp "$OURS_FILE" "$f"
      else
        cp "$OURS_FILE" "$f"
        CONFLICTED=$((CONFLICTED + 1))
        CONFLICT_FILES="$CONFLICT_FILES $f"
      fi
      rm -f "$BASE_FILE" "$OURS_FILE" "$THEIRS_FILE"
    fi
  done
done

if [ "$CONFLICTED" -lt 1 ]; then
  echo "FAIL Scenario B: expected ≥1 conflict, got $CONFLICTED"
  exit 1
fi

# Verify conflict markers exist in the conflicted file
if grep -qE '^<<<<<<< OURS' MR-Archon.md && grep -qE '^>>>>>>> THEIRS' MR-Archon.md; then
  echo "PASS Scenario B: conflict markers present in MR-Archon.md ($CONFLICTED file(s) conflicted)"
else
  echo "FAIL Scenario B: conflict markers missing"
  cat MR-Archon.md
  exit 1
fi

echo ""
echo "=== ALL SCENARIOS PASS ==="
