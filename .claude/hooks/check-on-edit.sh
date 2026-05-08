#!/usr/bin/env bash
# PostToolUse hook fired after Edit / Write / MultiEdit on a file in this repo.
#
# Per-edit gate: runs the linter (and per-file type checker for Python) on the
# file just modified. If issues are found, returns a JSON block decision that
# stops Claude until they're fixed. The agent sees the linter output via
# `additionalContext` and can address it in the next turn.
#
# Why per-edit and not per-iteration:
# - Smallest possible bug surface — failures point to the last change.
# - Forces Claude to fix as it goes instead of accumulating a wall of errors
#   that gets reported at the end of the iteration's feedback loop.
#
# What this hook does NOT do:
# - tsc --noEmit (runs project-wide; reserved for the feedback loop at iter end).
# - pytest / vitest (state-of-the-world tests, not per-edit).
# - generate-types regen (handled by the pre-commit hook).
#
# Quick exits (no block):
# - File deleted by the tool, or path not provided.
# - File outside backend/ or frontend/ (e.g., docs, configs).
# - Required CLI not on PATH (warn to stderr, exit 0).

set -uo pipefail

INPUT=$(cat)
# Defensive: if jq is missing or input isn't JSON, bail out so we don't break Claude.
if ! command -v jq >/dev/null 2>&1; then
  echo "[hook check-on-edit] jq not on PATH — skipping" >&2
  exit 0
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Emit a JSON `block` decision and exit 0 (the JSON is read; nonzero exit is
# treated as a hook crash, which doesn't surface the reason to Claude).
block() {
  local reason=$1
  local context=$2
  jq -nc \
    --arg reason "$reason" \
    --arg context "$context" \
    '{
      decision: "block",
      reason: $reason,
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $context
      }
    }'
  exit 0
}

ext="${FILE_PATH##*.}"
case "$ext" in
  py)
    [[ "$FILE_PATH" == *"/backend/"* ]] || exit 0
    cd "$PROJECT_DIR/backend" 2>/dev/null || exit 0

    if command -v uv >/dev/null 2>&1; then
      RUFF_OUT=$(uv run ruff check --output-format=concise "$FILE_PATH" 2>&1) || {
        block "Ruff found violations in $(basename "$FILE_PATH"). Fix before continuing." "$RUFF_OUT"
      }
      # Pyright per-file: ~1-2s, fast enough for per-edit gate.
      PYRIGHT_OUT=$(uv run pyright "$FILE_PATH" 2>&1 || true)
      ERROR_COUNT=$(printf '%s\n' "$PYRIGHT_OUT" | grep -oE "^[0-9]+ error" | head -1 | grep -oE "^[0-9]+" || echo 0)
      if [ "${ERROR_COUNT:-0}" -gt 0 ]; then
        block "Pyright reports ${ERROR_COUNT} type error(s) in $(basename "$FILE_PATH"). Fix before continuing." "$PYRIGHT_OUT"
      fi
    else
      echo "[hook check-on-edit] uv not on PATH — skipping Python checks" >&2
    fi
    ;;
  ts|tsx|js|jsx)
    [[ "$FILE_PATH" == *"/frontend/"* ]] || exit 0
    cd "$PROJECT_DIR/frontend" 2>/dev/null || exit 0

    if command -v bunx >/dev/null 2>&1; then
      BIOME_OUT=$(bunx biome check --no-errors-on-unmatched "$FILE_PATH" 2>&1) || {
        block "Biome found issues in $(basename "$FILE_PATH"). Fix before continuing." "$BIOME_OUT"
      }
    else
      echo "[hook check-on-edit] bunx not on PATH — skipping Biome check" >&2
    fi
    ;;
  *)
    # Other extensions (md, json, yaml, css, ...) — no per-edit gate.
    exit 0
    ;;
esac

exit 0
