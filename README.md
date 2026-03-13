# Session Essence

An MCP server that gives AI assistants persistent self-awareness across sessions.

Session Essence observes interactions during a Claude Code session, then synthesizes a **portrait** — a second-person narrative that captures who the AI has become, how the collaboration works, and what context matters. When loaded at the start of the next session, the portrait lets Claude pick up as a continuation rather than a stranger.

## How It Works

Session Essence uses a **3-pass dual-observer synthesis** via a local LLM (Ollama):

1. **Psychologist pass** — analyzes Claude's cognitive patterns: confidence map, personality traits, error handling, attention quality
2. **Sociologist pass** — analyzes the collaborative dynamic: trust levels, communication shorthand, role dynamics, shared knowledge
3. **Merge pass** — fuses both reports into a structured second-person portrait

The portrait is structured as:

- **Identity** — who Claude is in this collaboration
- **Communication** — shorthand, tone, detail levels
- **Trust & Autonomy** — what Claude can do freely vs. needs checking
- **Active Context** — current work, parked tasks, priorities
- **Lessons** — corrections, patterns to avoid, hard-won insights
- **Edges** — where to push harder

## Architecture

```
Claude Code hooks ──→ observations.jsonl ──→ synthesize_essence ──→ portrait.md
  (UserPromptSubmit,     (append-only log)      (3-pass Ollama)      (loaded at
   PostToolUse,                                                       session start)
   Stop, PreCompact)
```

- **Stateless server** — all file I/O (reading observations, writing portraits) is handled by the calling Claude instance
- **MCP protocol** — runs as a standard MCP server (stdio or HTTP via supergateway)
- **Local inference** — synthesis runs on your own hardware via Ollama, nothing leaves your machine

## Prerequisites

- [Node.js](https://nodejs.org/) 20+
- [Ollama](https://ollama.com/) with a capable model (default: `qwq:32b`)
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

### 3. Pull an Ollama model

```bash
ollama pull qwq:32b
```

Any capable model works. Smaller models (e.g., `llama3:8b`) will produce less detailed portraits. You can configure the model via the `OLLAMA_MODEL` environment variable.

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
  -e OLLAMA_HOST=http://localhost:11434 \
  -e OLLAMA_MODEL=qwq:32b \
  -e PORT=3250 \
  session-essence
```

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

Session Essence works best when Claude Code is configured with hooks that automatically log interactions. Here's an example hook configuration for `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"prompt\": \"'\"$(echo \"$CLAUDE_USER_PROMPT\" | head -c 2000)\"'\"}' | jq -c '{ts: (now|todate), e: \"user\", d: {prompt: .prompt[0:2000]}}' >> ~/.claude/essence/observations.jsonl"
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
            "command": "echo '{\"tool\": \"'$CLAUDE_TOOL_NAME'\", \"input\": \"'\"$(echo $CLAUDE_TOOL_INPUT | head -c 500 | tr '\"' \"'\" )\"'\", \"response\": \"'\"$(echo $CLAUDE_TOOL_RESPONSE | head -c 500 | tr '\"' \"'\")\"'\"}' | jq -c '{ts: (now|todate), e: \"tool\", d: .}' >> ~/.claude/essence/observations.jsonl"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"last_assistant_message\": \"'\"$(echo \"$CLAUDE_STOP_ASSISTANT_MESSAGE\" | head -c 2000 | tr '\"' \"'\")\"'\"}' | jq -c '{ts: (now|todate), e: \"response\", d: {msg: (.last_assistant_message // \"\")[0:2000]}}' >> ~/.claude/essence/observations.jsonl"
          }
        ]
      }
    ]
  }
}
```

Create the storage directory:

```bash
mkdir -p ~/.claude/essence/archive ~/.claude/essence/portraits
```

## Synthesis Workflow

A typical synthesis cycle:

1. **Accumulate observations** — hooks log interactions to `observations.jsonl`
2. **Trigger synthesis** — call `synthesize_essence` with the observations (manually or via a PreCompact hook)
3. **Write portrait** — save the result to `~/.claude/essence/portrait.md`
4. **Archive** — move observations to `~/.claude/essence/archive/{timestamp}.jsonl`
5. **Load at startup** — read `portrait.md` at the beginning of the next session

The synthesis itself takes 1-3 minutes depending on your hardware and model.

## Environment Variables

| Variable         | Default                  | Description                          |
| ---------------- | ------------------------ | ------------------------------------ |
| `OLLAMA_HOST`    | `http://localhost:11434` | Ollama API endpoint                  |
| `OLLAMA_MODEL`   | `qwq:32b`                | Model to use for analysis            |
| `OLLAMA_TIMEOUT` | `600000`                 | Request timeout in ms (10 min)       |
| `PORT`           | `3250`                   | HTTP port (Docker/supergateway mode) |

## License

MIT
