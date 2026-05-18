# AGENTS.md

Orientation for AI coding agents (Claude Code, Cursor, Aider, Codex, etc.) dropping into this repo. Humans should read [`README.md`](./README.md) instead — that doc is the operational reference. This one is the "what you need to know to make a sane change."

## What this project is

**Session Essence** is an MCP (Model Context Protocol) server that gives AI assistants persistent self-awareness across sessions. It synthesizes interaction logs into a **portrait** — a second-person narrative ("You are…") that Claude internalizes at session start.

- **Stack**: Node.js 20+, ESM (`"type": "module"`)
- **Runtime**: stdio MCP server (default) or HTTP via [supergateway](https://github.com/nicobailon/supergateway) (Docker)
- **Backends**: Claude API (default) or Ollama (opt-in via `SYNTHESIS_BACKEND=ollama`)
- **License**: MIT
- **Repo**: `github.com/dpdanpittman/session-essence`

The full design rationale lives in [`docs/design.md`](./docs/design.md) — read that BEFORE making any change to the synthesis logic, prompts, or portrait structure. Changes to those surfaces have outsized impact on user experience and shouldn't happen on instinct.

## How to build and run

```bash
# Install (no separate build step — pure ESM, no transpile)
npm install

# Personalize the prompts (REQUIRED before first run)
cp prompts.template.js prompts.js
# Then edit prompts.js — replace placeholder names with the operator's actual name

# Run the MCP server over stdio
node index.js

# Or run as an HTTP endpoint via Docker + supergateway
docker build -t session-essence .
docker run -d --network host -e ANTHROPIC_API_KEY=... -e PORT=3250 session-essence
```

There is **no test suite** as of this writing — `npm test` is unconfigured. If you're adding tests, propose the framework choice to the operator first; don't pull a test harness in unannounced.

## Key files

| Path                             | Role                                                                                                                                                                                                                                   |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `index.js`                       | The MCP server. Defines three tools (`synthesize_essence`, `format_observation`, `analyze_portrait`), the dual-backend chat dispatcher, and stdio transport setup. Single-file by design — there's no service layer to factor out yet. |
| `prompts.js`                     | **Gitignored. Personal.** Contains the three analytical system prompts (PSYCHOLOGIST, SOCIOLOGIST, MERGE) with the operator's actual name substituted in. Operators copy this from the template on install and never check it in.      |
| `prompts.template.js`            | The committed template with `"the human collaborator"` placeholders. Source of truth for the prompt structure. Edits to prompt logic happen HERE, not in `prompts.js`.                                                                 |
| `Dockerfile`                     | Multi-stage-ish build that wraps the stdio server in supergateway for HTTP. Sets `SYNTHESIS_BACKEND=claude` by default. Operators who want Ollama override at `docker run` time.                                                       |
| `package.json`                   | Three dependencies: `@modelcontextprotocol/sdk` (MCP framework), `@anthropic-ai/sdk` (Claude backend), `supergateway` (Docker HTTP wrapping). Keep this list short; new deps need justification.                                       |
| `docs/design.md`                 | The "why" doc. Architectural decisions + their reasoning. Read before changing synthesis behavior.                                                                                                                                     |
| `examples/synthesize-essence.sh` | Reference PreCompact hook script. Spawns a detached `claude -p` to surgically edit the long-form portrait. Lives in the repo as documentation; the operator places it at `~/.claude/scripts/`.                                         |
| `README.md`                      | Human-facing operational reference.                                                                                                                                                                                                    |

## Conventions

- **ESM only.** `"type": "module"` in `package.json` — use `import` / `export`, not `require`.
- **Zod for tool schemas.** Every MCP tool's input schema uses `z.object({ ... })`. Match the existing pattern.
- **Explicit env-var config.** No `.env` files, no config files. Every runtime knob is an env var (`SYNTHESIS_BACKEND`, `ANTHROPIC_API_KEY`, `CLAUDE_MODEL`, `OLLAMA_HOST`, etc.). Add new env vars to the table in README.md AND default them in `index.js`.
- **Stateless server.** The MCP server itself does **no file I/O**. It does not read `observations.jsonl`, it does not write `portrait.md`. The calling Claude instance handles all local file work via Read/Write tools. If you're tempted to add `fs` calls inside `index.js`, stop and re-read `docs/design.md` — this constraint is load-bearing.
- **Prompts are versioned in `prompts.template.js`.** When you change a prompt, change it in the template. The operator's local `prompts.js` is downstream of the template.
- **Single-file server.** `index.js` is one ~340-line file by design. Don't pre-emptively split it into modules — the cohesion benefits beat the file-count tidiness until there's actual reason to split.

## Gotchas

- **`prompts.js` is gitignored** because it contains the operator's personal name. Before you can run the server, `cp prompts.template.js prompts.js`. If you're testing in CI, you'll need to either commit a test fixture variant or generate one on the fly.
- **Claude Code hook format changed.** The README's hook examples use the modern stdin-JSON format (`INPUT=$(cat); echo "$INPUT" | jq …`). Older docs and tutorials use `$CLAUDE_USER_PROMPT` env-var style — that pattern is dead in current Claude Code and produces empty observations silently. If you're tempted to "simplify" the hooks back to env vars, don't.
- **The two synthesis paths are different by design.** The MCP `synthesize_essence` tool does a clean 3-pass regeneration. The PreCompact `synthesize-essence.sh` script does a **surgical edit** via a detached `claude -p`. These are NOT redundant — see `docs/design.md` "Why surgical edits, not regeneration."
- **`@anthropic-ai/sdk` does not need to be a hard dependency for Ollama-only deployments**, but right now it is. Removing it would require a dynamic import; left for later.
- **Min-observations guard is in code, not in the MCP schema.** `index.js` rejects synthesis when fewer than 10 observations are present (and the PreCompact script requires 15). Don't move this check into the zod schema — it's about runtime state, not input validation.
- **Portrait sections 7-9 (Episodes, Voice, Decisions) are produced by the surgical-edit script, not by `MERGE_SYSTEM` in `prompts.template.js`.** If you're looking at the merge prompt and wondering why it only generates 6 sections, that's why. The extended sections grow through a separate process.

## Deployment context (for changes affecting prod)

The maintainer runs this as a Docker container on a host machine (`zaphod-beeblebox@192.168.6.56`), exposed at `http://192.168.6.56:3250/mcp` via supergateway, with `--restart unless-stopped`. The container talks to Anthropic's API by default. Changes that affect Docker build behavior, port bindings, or HTTP semantics will land there first — call them out in your PR description.

The repo is **also symlinked** into a larger MCP server stack (`mcp-server-stack/servers/session-essence`) for ergonomic local development. Don't add hard paths to either repo's directory layout that would break the symlink relationship.

## When in doubt

- For **prompt changes**: read `docs/design.md` first, especially "Why second person" and "Why dual observers."
- For **synthesis flow changes**: read `docs/design.md` "Why surgical edits."
- For **MCP tool surface changes**: keep the existing three tools' contracts stable. New tools fine; renames or schema changes need operator approval.
- For **dependency additions**: argue for it in the PR. Three deps is a feature, not a limitation.
