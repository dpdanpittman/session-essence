# P-session-essence-audit — Intent

First Tribunal audit of the `session-essence` repo. Goal: shake out defects the docs don't mention, behaviors that diverge from documentation, and security / correctness / portability holes before this gets adopted outside Dan's own workflow.

## What this repo is

`session-essence` is an MCP (Model Context Protocol) server that gives AI assistants persistent self-awareness across sessions. It synthesizes interaction logs into a second-person **portrait** ("You are…") that Claude internalizes at session start. The portrait captures three inseparable things: who Claude has become (personality), what Claude knows (context + decisions), and how the collaboration works (trust + shorthand).

- **Stack**: Node.js 20+, ESM, single-file MCP server (`index.js`, ~340 LOC).
- **Dual backend**: Claude API (`claude-haiku-4-5-20251001` by default) or Ollama (`qwq:32b`). Selected via `SYNTHESIS_BACKEND` env var; default is `claude`.
- **Three MCP tools**:
  - `synthesize_essence` — runs the 3-pass dual-observer synthesis (psychologist → sociologist → merge)
  - `format_observation` — emits a JSONL observation line for manual logging
  - `analyze_portrait` — diffs two portraits
- **Three system prompts**: `PSYCHOLOGIST_SYSTEM`, `SOCIOLOGIST_SYSTEM`, `MERGE_SYSTEM` (in `prompts.template.js`, personalized into local `prompts.js`).
- **Deployment**: standalone stdio, or Dockerized with `supergateway` exposing the MCP server as HTTP at `:3250`. Maintainer runs it as a long-lived container on `192.168.6.56`.

## What's expected to be true

These are the load-bearing claims this audit should pressure-test:

1. **The MCP tools are stateless.** `index.js` does no file I/O — `observations.jsonl` and `portrait.md` are read/written by the calling Claude instance. This is a documented architectural constraint (see `docs/design.md` "Why stateless").

2. **The two backends produce equivalent portraits.** `chat()` dispatches to either `claudeChat()` or `ollamaChat()` based on `SYNTHESIS_BACKEND`; the rest of the code shouldn't observe which ran. Operators should be able to switch backends without resetting their portrait.

3. **The min-observations guard fires before any backend call.** `synthesize_essence` rejects with "Insufficient observations" when fewer than 10 lines of input are present, BEFORE incurring any token cost.

4. **The observation truncation is bounded.** Only the last 200 observations are passed to the backend; older lines are discarded. This caps the context size sent to the LLM regardless of how large the operator's `observations.jsonl` has grown.

5. **The Anthropic client is lazily initialized.** `getAnthropicClient()` only constructs the `Anthropic` instance on first use, and only checks `ANTHROPIC_API_KEY` then. Ollama-only deployments shouldn't fail to start just because the key isn't set.

6. **The hooks in the README use the modern Claude Code event format.** They read the event payload as JSON from stdin (`INPUT=$(cat); echo "$INPUT" | jq …`), not from `$CLAUDE_*` env vars (a pattern that's dead in current Claude Code and produces empty observations silently).

7. **The PreCompact script (`examples/synthesize-essence.sh`) is safe under concurrent invocation.** It uses a `.synthesis-running` lock file. Multiple PreCompact firings shouldn't double-dispatch.

8. **Personalization is explicit, not auto-magic.** `prompts.js` is gitignored; the operator must copy `prompts.template.js → prompts.js` and edit it. There's no silent fallback or vendor identity baked in.

9. **No file under this repo writes to `~/.claude/essence/`.** The MCP server itself is stateless; only the operator-installed PreCompact script touches the operator's home directory.

10. **The synthesis output's "Analysis Details" section is collapsed by default.** The portrait is the primary artifact; the per-observer reports are appendix material in a `<details>` HTML block.

## Diff under review

Two commits land between the previous `main` and HEAD:

- `9b1436e feat: dual-backend synthesis (Claude API default, Ollama fallback)` — adds `claudeChat()`, the `chat()` dispatcher, `Anthropic` SDK as a dependency, Claude-related env vars, and Dockerfile defaults pointing at the Claude backend.
- `5b1f381 docs: README rewrite, AGENTS.md, design.md, example PreCompact script` — full README rewrite (dual-backend, fixed hook examples, troubleshooting), new `docs/design.md`, new `AGENTS.md`, new `examples/synthesize-essence.sh`.

Audit scope is the full repo at HEAD, not just the diff. This is the first time Tribunal has seen this codebase, so the lens trio should treat the entire `index.js` + `prompts.template.js` + `Dockerfile` + `package.json` + `examples/synthesize-essence.sh` as in-scope.

## Out of scope

- The `prompts.js` personal file (gitignored; per-operator).
- The `node_modules/` tree.
- Reviewing the docs themselves as docs (the audit treats them as the source of expected behavior — the question is whether the CODE matches them).

## Verdict criteria

- **Critical**: defects that break a stated guarantee (e.g., a tool secretly writes to disk, the Ollama path fails when `ANTHROPIC_API_KEY` is unset, the min-observations guard can be bypassed) or that introduce a security exposure (e.g., prompt injection vectors via observations, shell injection in the PreCompact script, credential leakage).
- **Warning**: behaviors that diverge from the docs without breaking guarantees, missing input validation that could matter under non-pathological inputs, portability gaps (works on Dan's machine, breaks elsewhere).
- **Suggestion**: code quality observations, missing tests, improvable error messages, dead code.

The verdict gate for this audit is the same as any Tribunal review: all three lenses Approve → adversary runs → adversary verdict gates merge readiness.
