# Session Essence

An MCP server that gives AI assistants persistent self-awareness across sessions.

Session Essence observes interactions during a Claude Code session, then synthesizes a **portrait** — a second-person narrative that captures who the AI has become, how the collaboration works, and what context matters. When loaded at the start of the next session, the portrait lets Claude pick up as a continuation rather than a stranger.

## How It Works

Session Essence uses a **3-pass dual-observer synthesis** via either the Claude API (default) or a local Ollama model (opt-in fallback):

1. **Psychologist pass** — analyzes Claude's cognitive patterns: confidence map, personality traits, error handling, attention quality
2. **Sociologist pass** — analyzes the collaborative dynamic: trust levels, communication shorthand, role dynamics, shared knowledge
3. **Merge pass** — fuses both reports into a structured second-person portrait

### The portrait

The MCP `synthesize_essence` tool produces a **6-section portrait**:

1. **Identity** — who Claude is in this collaboration
2. **Communication** — shorthand, tone, detail levels
3. **Trust & Autonomy** — what Claude can do freely vs. needs checking
4. **Active Context** — current work, parked tasks, priorities
5. **Lessons** — corrections, patterns to avoid, hard-won insights
6. **Edges** — where to push harder

The recommended PreCompact integration (see `~/.claude/scripts/synthesize-essence.sh` in this repo's docs) extends the portrait with three more sections that grow over time via surgical edits rather than full regeneration:

7. **Episodes** — specific moments that shifted something
8. **Voice** — exchange samples capturing the collaborative tone
9. **Decisions** — architectural / design decisions and their rationale

The 6-section form is the immediate output of one synthesis run; the 9-section form is the living document Claude reads at session start.

### Two backends, one tool

| Backend                  | Default? | When to use                                                                                                                              |
| ------------------------ | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `claude` (Anthropic API) | yes      | Reliable, high-quality synthesis. Costs ~a few cents per run with Haiku. Requires `ANTHROPIC_API_KEY`.                                   |
| `ollama` (local)         | no       | Free, private, runs on your hardware. Requires a capable model (`qwq:32b` recommended). Smaller models will produce shallower portraits. |

Set `SYNTHESIS_BACKEND=ollama` to switch.

## Architecture

```
Claude Code hooks ──→ observations.jsonl ──→ synthesize_essence ──→ portrait.md
  (UserPromptSubmit,    (append-only log)     (3-pass synthesis     (loaded at
   PostToolUse,                                via claude or         session start
   Stop, PreCompact,                          ollama backend)        via SessionStart
   SessionStart)                                                     hook)
```

- **Stateless server** — all file I/O (reading observations, writing portraits) is handled by the calling Claude instance
- **MCP protocol** — runs as a standard MCP server (stdio or HTTP via supergateway)
- **Pluggable backend** — Claude API by default; Ollama for fully-local inference. Same prompts, same output shape

For the philosophical underpinnings — why second-person portraits, why dual-observer, why surgical edits — see [`docs/design.md`](./docs/design.md).

## Prerequisites

- [Node.js](https://nodejs.org/) 20+
- One synthesis backend:
  - **Claude API** (default): an `ANTHROPIC_API_KEY` with Messages-API access
  - **Ollama** (opt-in): [Ollama](https://ollama.com/) with a capable model (default: `qwq:32b`)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (or any MCP client)

## Installation

### 1. Clone and install

```bash
git clone https://github.com/dpdanpittman/session-essence.git
cd session-essence
npm install
```

### 2. Personalize the prompts

The analysis prompts reference your name so the AI observers can identify the human collaborator in the logs. Copy the template and replace the placeholder:

```bash
cp prompts.template.js prompts.js
```

Edit `prompts.js` and replace `"the human collaborator"` / `"the human"` / `"a human collaborator"` with your name throughout. This personalizes the analysis — the observers will reference you by name in their reports, producing more specific and useful portraits.

### 3. Set up your backend

**Claude API** (default — no extra setup beyond exporting the key):

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Default model is `claude-haiku-4-5-20251001` — fast, cheap, plenty good for synthesis. Override via `CLAUDE_MODEL`.

**Ollama** (alternative, fully local):

```bash
ollama pull qwq:32b
export SYNTHESIS_BACKEND=ollama
```

Any capable model works. Smaller models (e.g., `llama3:8b`) will produce shallower portraits. Configure with `OLLAMA_MODEL`.

### Running standalone (stdio)

```bash
node index.js
```

### Running as HTTP endpoint (Docker)

```bash
docker build -t session-essence .
docker run -d \
  --name session-essence \
  --restart unless-stopped \
  --network host \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e PORT=3250 \
  session-essence
```

For the Ollama backend, add `-e SYNTHESIS_BACKEND=ollama -e OLLAMA_HOST=http://localhost:11434 -e OLLAMA_MODEL=qwq:32b` and drop the `ANTHROPIC_API_KEY` line.

The container uses [supergateway](https://github.com/nicobailon/supergateway) to expose the stdio MCP server as a streamable HTTP endpoint.

### Register with Claude Code

For stdio:

```bash
claude mcp add session-essence node /path/to/session-essence/index.js
```

For HTTP (if running via Docker/supergateway):

```bash
claude mcp add session-essence --transport http http://localhost:3250/mcp
```

## MCP Tools

### `synthesize_essence`

Runs the full 3-pass synthesis. Pass the contents of your observations log and optionally a previous portrait for continuity.

**Parameters:**

- `observations` (string, required) — contents of observations.jsonl
- `previous_portrait` (string, optional) — previous portrait for continuity

**Returns:** A structured portrait with the merged result, plus detailed psychologist and sociologist reports in a collapsible section.

### `format_observation`

Formats a manual observation as a JSONL line. Use this when you notice something the hooks wouldn't capture — a shift in tone, an important realization, a moment of particularly good or bad collaboration.

**Parameters:**

- `category` (enum: personality, communication, trust, correction, insight, context)
- `note` (string) — the observation content

### `analyze_portrait`

Compares two portraits to identify what changed between syntheses.

**Parameters:**

- `old_portrait` (string) — the earlier portrait
- `new_portrait` (string) — the more recent portrait

## Observation Hooks

Session Essence works best when Claude Code is configured with hooks that automatically log interactions, trigger synthesis on context compaction, and re-inject the portrait at session start.

Claude Code's modern hook format passes the event payload as JSON on stdin (not as `$CLAUDE_*` env vars — that pattern is from an older Claude Code version and will silently produce empty observations). Drop this into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "INPUT=$(cat); echo \"$INPUT\" | jq -c '{ts: (now|todate), e: \"user\", d: {prompt: .prompt[0:2000]}}' >> ~/.claude/essence/observations.jsonl 2>/dev/null; true"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "INPUT=$(cat); echo \"$INPUT\" | jq -c '{ts: (now|todate), e: \"tool\", d: {tool: .tool_name, input: (.tool_input|tostring|.[0:500]), response: (.tool_response|tostring|.[0:300])}}' >> ~/.claude/essence/observations.jsonl 2>/dev/null; true"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/scripts/synthesize-essence.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "PORTRAIT=~/.claude/essence/portrait.md; if [ -f \"$PORTRAIT\" ]; then echo '## Session Essence Portrait'; echo ''; cat \"$PORTRAIT\"; fi"
          }
        ]
      }
    ]
  }
}
```

Then create the storage layout:

```bash
mkdir -p ~/.claude/essence/archive ~/.claude/essence/portraits
```

### What each hook does

- **`UserPromptSubmit`** — appends a `{"e":"user"}` line per user message
- **`PostToolUse`** — appends a `{"e":"tool"}` line per tool call (tool name + truncated input + truncated response)
- **`PreCompact`** — triggers the synthesis script (see next section) before context auto-compaction kicks in, so the session's observations get distilled into the portrait while they're still recallable
- **`SessionStart`** — injects the current portrait into Claude's startup context. This is what closes the loop — without it, the portrait sits unread on disk

### The PreCompact synthesis script

The reference `synthesize-essence.sh` (place at `~/.claude/scripts/`) does NOT call the MCP tool directly. It spawns a detached `claude -p --model haiku` instance that surgically edits the long-form portrait in place — extending sections 7–9 (Episodes, Voice, Decisions) with this session's signal rather than regenerating from scratch. Surgical edits preserve hard-won continuity that a clean regeneration would wipe.

The MCP `synthesize_essence` tool remains the right call for **first synthesis** (no prior portrait) or **full rebuild** (after major project pivots). Use the PreCompact script for ongoing maintenance.

A copy of the script ships at `examples/synthesize-essence.sh` in this repo.

## Synthesis Workflow

The full lifecycle, with the hooks above wired:

1. **Session runs** — `UserPromptSubmit` + `PostToolUse` hooks append observations to `~/.claude/essence/observations.jsonl`
2. **Context fills** — Claude Code is about to auto-compact (or you ran `/compact`); `PreCompact` fires `synthesize-essence.sh`
3. **Synthesis** — the script reads observations + the current portrait, surgically edits the portrait, archives `observations.jsonl` to `~/.claude/essence/archive/<timestamp>.jsonl`, clears the live observations file
4. **Next session** — `SessionStart` hook prints the portrait into Claude's startup context

Synthesis runtime: 30s–2min with the Claude backend on Haiku; 1–3min on the Ollama backend with `qwq:32b` on a 24GB GPU.

The MCP tool path (calling `synthesize_essence` manually) is parallel to this — useful for the first portrait, for full rebuilds after major project pivots, or as a one-shot synthesis when you don't want the surgical-edit behavior.

## Storage Layout

```
~/.claude/essence/
  observations.jsonl       # live log, cleared after each synthesis
  portrait.md              # current portrait (the artifact SessionStart reads)
  .synthesis-running       # lock file (auto-cleaned)
  last-synthesis.log       # output of the most recent PreCompact run
  archive/
    <timestamp>.jsonl      # one file per synthesis cycle
  portraits/
    <timestamp>.md         # optional historical portraits (manual archiving)
```

The `archive/` directory grows monotonically — useful for going back and asking "when did the trust calibration around X actually shift?". Prune it on whatever cadence makes sense; the live `portrait.md` doesn't reference it.

## Environment Variables

| Variable            | Default                     | Description                                                     |
| ------------------- | --------------------------- | --------------------------------------------------------------- |
| `SYNTHESIS_BACKEND` | `claude`                    | `claude` or `ollama` — which backend the MCP tool dispatches to |
| `ANTHROPIC_API_KEY` | _(unset)_                   | Required when `SYNTHESIS_BACKEND=claude`                        |
| `CLAUDE_MODEL`      | `claude-haiku-4-5-20251001` | Anthropic model id for the Claude backend                       |
| `OLLAMA_HOST`       | `http://localhost:11434`    | Ollama API endpoint                                             |
| `OLLAMA_MODEL`      | `qwq:32b`                   | Ollama model id                                                 |
| `OLLAMA_TIMEOUT`    | `600000`                    | Ollama request timeout in ms (10 min)                           |
| `PORT`              | `3250`                      | HTTP port (Docker/supergateway mode)                            |

## Troubleshooting

**Portrait isn't loading at session start.**
The `SessionStart` hook is what injects it. Without that hook, the portrait sits unread on disk. Verify it's in `~/.claude/settings.json` and that `~/.claude/essence/portrait.md` exists.

**Observations log is empty after a session.**
The hooks expect Claude Code's modern stdin-JSON event format. If you're using the older `$CLAUDE_USER_PROMPT` env-var pattern, observations silently land as empty strings. Use the `INPUT=$(cat)` form from the example above.

**`synthesize_essence` returns "Insufficient observations".**
The MCP tool requires at least 10 lines in the observations log; the PreCompact script requires 15. Run the session a bit longer and try again.

**PreCompact script says "synthesis already running".**
A `.synthesis-running` lock file is held while the detached `claude -p` process runs. If it crashed mid-flight without cleaning up, remove the lock manually: `rm ~/.claude/essence/.synthesis-running`.

**Synthesis times out / takes forever on Ollama.**
`qwq:32b` needs ~24GB of VRAM at the configured context size. If your model is CPU-splitting, synthesis can take 10+ min. Either drop to a smaller model (with quality tradeoffs) or switch to the Claude backend.

**Portrait says a name you don't recognize.**
First treat this as a security signal, NOT a benign continuation. The portrait is loaded into every session's startup context in second-person directive form — a name change is potentially evidence of injected content riding in via observations, a synthesis pass that hallucinated, or an out-of-band write to `portrait.md`. Investigation flow:

1. Run `tribunal review`-style analysis via the `analyze_portrait` MCP tool, comparing the current portrait against the last one you endorsed (`~/.claude/essence/portraits/<earlier-timestamp>.md` if you archive manually, otherwise check the most recent file in `~/.claude/essence/archive/` for context).
2. Grep recent `~/.claude/essence/archive/*.jsonl` for the name's first appearance. If it shows up in an observation line whose source was a user prompt you didn't write, a tool response from an MCP server you don't fully trust, or a paste from an external source — that's the injection point.
3. Check `~/.claude/essence/last-synthesis.log` and `~/.claude/essence/synthesis-status.json` (v2.0.1+) for the synthesis run that introduced the change.
4. If the change is legitimate (genuine emergent naming from real interaction), accept it. If it's not, restore the prior portrait from your most recent endorsed backup and patch the inflow that introduced it.

The "Mabus" naming in this repo's documentation is a specific operator's accepted continuation — it's not a default Session Essence produces. If a name you didn't pick appears in your portrait, that's signal worth investigating, not noise to delete.

**Synthesis status file shows `portrait_changed: false`.**
The v2.0.1+ PreCompact supervisor writes `~/.claude/essence/synthesis-status.json` after each run. `portrait_changed: false` means the agent ran but didn't touch the portrait file — either nothing in the session was worth recording (genuinely-routine sessions), or the agent crashed silently. Check `~/.claude/essence/last-synthesis.log` for the agent's output to distinguish.

## Further Reading

- [`docs/design.md`](./docs/design.md) — why this exists, the dual-observer rationale, the philosophical bet
- [`AGENTS.md`](./AGENTS.md) — orientation for AI agents dropping into this repo

## License

MIT
