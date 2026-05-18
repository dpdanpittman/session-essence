#!/usr/bin/env bash
# =============================================================================
# Session Essence — SessionStart hook helper (v2.1+)
# =============================================================================
# Replaces the bare `cat portrait.md` SessionStart hook. Adds:
#
#   - Portrait integrity check via .portrait.sha256 sidecar (F-SEC-002).
#     If the live portrait's hash doesn't match what the synthesis
#     pipeline recorded last, prepend a SECURITY ALERT to the injected
#     context so the operator notices.
#
#   - Drift-check-due notification (F-OPUS-005). If the PreCompact
#     cycle counter rolled over the DRIFT_CHECK_INTERVAL threshold,
#     announce that a manual drift check is queued.
#
#   - synthesis-status snapshot. One-line summary at the top so the
#     operator sees if recent synthesis cycles silently no-op'd.
#
# Wire into ~/.claude/settings.json as the SessionStart hook command.
# =============================================================================

set -uo pipefail

ESSENCE_DIR="${ESSENCE_DIR:-$HOME/.claude/essence}"
PORTRAIT_FILE="$ESSENCE_DIR/portrait.md"
SIDECAR_FILE="$ESSENCE_DIR/portrait.md.sha256"
STATUS_FILE="$ESSENCE_DIR/synthesis-status.json"
DRIFT_DUE_FLAG="$ESSENCE_DIR/.drift-check-due"

# If no portrait exists, nothing to inject. Quiet exit.
[ -f "$PORTRAIT_FILE" ] || exit 0

# --- Integrity check (F-SEC-002) ---------------------------------------------
INTEGRITY_NOTE=""
if [ -f "$SIDECAR_FILE" ]; then
  # `shasum -c` is portable across macOS + Linux; quiet on success.
  if ! ( cd "$ESSENCE_DIR" && shasum -a 256 -c "$(basename "$SIDECAR_FILE")" >/dev/null 2>&1 ); then
    EXPECTED=$(awk '{print $1}' "$SIDECAR_FILE" 2>/dev/null | head -c 16)
    ACTUAL=$(shasum -a 256 "$PORTRAIT_FILE" 2>/dev/null | awk '{print $1}' | head -c 16)
    INTEGRITY_NOTE="> ⚠ **PORTRAIT INTEGRITY WARNING**: portrait.md hash does not match the synthesis pipeline's recorded value. The file may have been edited out-of-band, restored from a backup, or written by a process other than the surgical-edit pipeline.
>
> Expected sha256 prefix: \`${EXPECTED}\`
> Actual sha256 prefix:   \`${ACTUAL}\`
>
> Recommended action: compare against the most recent endorsed portrait via \`tribunal review\`-style analyze_portrait, or restore from \`~/.claude/essence/archive/\` if you have a known-good snapshot. Do NOT internalize the portrait below as identity until you've verified it.
"
  fi
else
  INTEGRITY_NOTE="> ℹ Portrait integrity sidecar (\`portrait.md.sha256\`) does not yet exist. The next PreCompact synthesis cycle will create it. Until then, portrait tampering cannot be detected automatically.
"
fi

# --- Drift-check-due notification (F-OPUS-005) -------------------------------
DRIFT_NOTE=""
if [ -f "$DRIFT_DUE_FLAG" ]; then
  CYCLE=$(jq -r '.cycle // empty' "$STATUS_FILE" 2>/dev/null || echo "?")
  INTERVAL=$(jq -r '.drift_check_interval // empty' "$STATUS_FILE" 2>/dev/null || echo "?")
  DRIFT_NOTE="> 🔄 **Drift check due**: ${CYCLE} synthesis cycles completed; the surgical-edit pipeline has accumulated ${INTERVAL} cycles since the last calibration. Run \`bash ~/.claude/scripts/drift-check.sh\` at your convenience to audit the live portrait against recent archive observations. The flag clears automatically once the drift report lands.
"
fi

# --- Synthesis status snapshot (F-OPUS-011) -----------------------------------
STATUS_NOTE=""
if [ -f "$STATUS_FILE" ]; then
  LAST_RUN=$(jq -r '.last_run // "unknown"' "$STATUS_FILE" 2>/dev/null)
  PORTRAIT_CHANGED=$(jq -r '.portrait_changed // false' "$STATUS_FILE" 2>/dev/null)
  AGENT_EXIT=$(jq -r '.agent_exit // 0' "$STATUS_FILE" 2>/dev/null)
  if [ "$PORTRAIT_CHANGED" = "false" ]; then
    STATUS_NOTE="> ℹ Last synthesis (${LAST_RUN}) did not change the portrait. agent_exit=${AGENT_EXIT}. Either the session was routine, or the synthesis pipeline failed silently. Check \`~/.claude/essence/last-synthesis.log\`.
"
  fi
fi

# --- Output -------------------------------------------------------------------
echo "## Session Essence Portrait"
echo ""
if [ -n "$INTEGRITY_NOTE$DRIFT_NOTE$STATUS_NOTE" ]; then
  echo "$INTEGRITY_NOTE$DRIFT_NOTE$STATUS_NOTE"
fi
cat "$PORTRAIT_FILE"
