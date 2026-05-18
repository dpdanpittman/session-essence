#!/usr/bin/env bash
# =============================================================================
# Session Essence Synthesis — triggered by PreCompact hook
# =============================================================================
# Spawns a detached claude -p instance that surgically edits the portrait,
# adds episodic moments and voice samples, archives observations, and cleans
# up. Uses Haiku for speed/cost via Max subscription.
# =============================================================================

ESSENCE_DIR="$HOME/.claude/essence"
OBS_FILE="$ESSENCE_DIR/observations.jsonl"
PORTRAIT_FILE="$ESSENCE_DIR/portrait.md"
ARCHIVE_DIR="$ESSENCE_DIR/archive"
LOCK_FILE="$ESSENCE_DIR/.synthesis-running"

# Guard: don't run if already running or too few observations
if [ -f "$LOCK_FILE" ]; then
  echo "Essence: synthesis already running, skipping."
  exit 0
fi

OBS_COUNT=$(wc -l < "$OBS_FILE" 2>/dev/null || echo 0)
if [ "$OBS_COUNT" -lt 15 ]; then
  echo "Essence: only $OBS_COUNT observations, skipping synthesis (need 15+)."
  exit 0
fi

# Create lock
touch "$LOCK_FILE"
mkdir -p "$ARCHIVE_DIR"

# Build the prompt
read -r -d '' PROMPT << 'SYNTHESIS_PROMPT'
You are updating a session essence portrait — a living document that gives future Claude instances continuity across sessions. This is NOT a rewrite. It is a surgical edit.

## Steps

1. Read ~/.claude/essence/observations.jsonl (interaction observations from hooks)
2. Read ~/.claude/essence/portrait.md (current portrait)
3. Make SURGICAL EDITS to the portrait based on what the observations show:

### Sections 1-6 (IDENTITY, COMMUNICATION, TRUST, CONTEXT, LESSONS, EDGES):
- EDIT existing text — change specific phrases, add new sentences, remove outdated info
- Do NOT regenerate these sections from scratch
- Only change what the observations give you evidence for
- Keep everything that's still true — most of it will be

### Section 7 (EPISODES):
- Add 1-3 new episodes from this session IF they represent significant moments
- An episode is a specific moment that reveals something about the relationship or shifted something
- Format: **"Quote or title" (date)**: 2-3 sentences describing what happened and why it matters
- Don't add routine work as episodes — only moments that changed something
- Keep all existing episodes unless they're clearly wrong

### Section 8 (VOICE):
- Add 1-2 new exchange samples IF the observations contain good examples of the collaborative tone
- These should be actual back-and-forth that captures how Dan and Claude talk
- Show the pattern, not just the words — include a note about WHY this exchange is representative
- Keep all existing voice samples

### Section 9 (DECISIONS):
- Add any significant architectural or design decisions made this session
- Format: **Decision name**: What was decided and WHY — the reasoning matters more than the outcome
- Keep all existing decisions unless they were explicitly reversed

4. Write the updated portrait to ~/.claude/essence/portrait.md
5. Archive: run `cp ~/.claude/essence/observations.jsonl ~/.claude/essence/archive/$(date +%Y%m%d-%H%M%S).jsonl`
6. Clear observations: write empty content to ~/.claude/essence/observations.jsonl
7. Remove ~/.claude/essence/.needs-synthesis if it exists (use Bash rm -f)

## Rules
- Second person voice throughout ("You are...", "You own...")
- Be specific — cite what you saw in the observations, don't invent
- If the observations are mostly routine (tool calls, no significant interactions), make minimal edits and say so in the log
- Preserve the markdown structure exactly (## header, ### numbered sections)
- Don't add generic AI advice — every line should be earned from actual interaction
SYNTHESIS_PROMPT

# Run detached — output to log file for debugging
nohup claude -p \
  --model haiku \
  --allowedTools "Read Write Bash" \
  --permission-mode bypassPermissions \
  --no-session-persistence \
  "$PROMPT" \
  > "$ESSENCE_DIR/last-synthesis.log" 2>&1 &

# Clean up lock after the process finishes (poll for completion)
CLAUDE_PID=$!
(while kill -0 $CLAUDE_PID 2>/dev/null; do sleep 5; done; rm -f "$LOCK_FILE"; echo "Essence: synthesis complete at $(date)" >> "$ESSENCE_DIR/last-synthesis.log") &

echo "Essence: synthesis launched (pid $CLAUDE_PID, $OBS_COUNT observations)."
