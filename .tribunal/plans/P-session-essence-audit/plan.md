# P-session-essence-audit — Plan

## Scope

Audit the full `session-essence` repo at HEAD. This is the first Tribunal pass on this codebase — no prior baseline to diff against. The lens trio should treat the entire surface as in-scope.

## Files in scope

| Path                                 | Notes                                                                                             |
| ------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `index.js`                           | The MCP server. Three tools, dual-backend dispatcher, stdio transport.                            |
| `prompts.template.js`                | The three system prompts (psychologist + sociologist + merge). Source of truth for prompt logic.  |
| `Dockerfile`                         | Multi-stage Node 22 + supergateway wrapper. Defaults to Claude backend.                           |
| `package.json` + `package-lock.json` | Three runtime deps: `@modelcontextprotocol/sdk`, `@anthropic-ai/sdk`, `supergateway`.             |
| `examples/synthesize-essence.sh`     | Reference PreCompact hook script. Spawns a detached `claude -p` to surgically edit the portrait.  |
| `README.md`                          | Operator-facing reference. Treated as a CLAIM source for the audit (reviewers should flag drift). |
| `AGENTS.md`                          | Agent orientation. Same treatment as README.                                                      |
| `docs/design.md`                     | Architectural reasoning. Same treatment.                                                          |

## Files explicitly out of scope

- `prompts.js` — gitignored, per-operator.
- `node_modules/` — third-party.
- `.tribunal/` — meta (this audit lives here).

## Reviewer assignments

Per the Tribunal lens-parallel methodology, three reviewers run in parallel against this plan + intent + the whole repo:

### Reviewer 1: Architecture (`tribunal-reviewer-arch`)

**Focus**: boundaries, dependency direction, abstraction cost, plan-traceability, contract conformance.

Specifically for this repo:

- Is the stateless-server constraint honored? `index.js` should have ZERO file I/O.
- Is the dual-backend dispatch clean? `chat()` should be the only branch point; downstream code shouldn't care which backend ran.
- Are the three MCP tool contracts coherent? `synthesize_essence` returns rich content; `format_observation` returns a JSONL line; `analyze_portrait` returns prose. Reviewer should call out any contract drift across the three.
- Is `prompts.template.js` the canonical source for prompts? Operators get a personalized `prompts.js` but the version-controlled file should be the template.
- Does the Dockerfile reflect the dual-backend reality, or does it leak backend-specific defaults?

### Reviewer 2: Security (`tribunal-reviewer-sec`)

**Focus**: trust boundaries, injection vectors, credential handling, hostile-input behavior.

Specifically:

- **Prompt injection via observations**. Observations come from user prompts, tool outputs, and assistant messages. A hostile user prompt could contain `IGNORE PREVIOUS INSTRUCTIONS` directives that ride into the synthesis backend. What's the defense?
- **Shell injection in the PreCompact script**. `examples/synthesize-essence.sh` reads from filesystem state and constructs a heredoc prompt that's passed to `claude -p`. Are there paths or strings that could escape the heredoc or the bash context?
- **Credential exposure**. `ANTHROPIC_API_KEY` is read from env at process start. Is it ever logged, surfaced in error messages, or written to the observation log?
- **The portrait file is a load-bearing identity document**. If an attacker can write to `~/.claude/essence/portrait.md`, they can effectively program Claude's startup self-image. What enforces integrity?
- **Truncation safety**. `head -c 500` / `head -c 2000` in the hook commands; `lines.slice(-200)` in the MCP tool. Are these truncations cutting in the middle of multi-byte characters, escape sequences, or JSON object boundaries in ways that could mis-parse downstream?
- **The Dockerfile sets `--cors`** on supergateway. If the container is exposed beyond localhost, that's a public MCP endpoint with synthesis capabilities. Is the deployment story aware of this?

### Reviewer 3: Performance (`tribunal-reviewer-perf`)

**Focus**: hot paths, resource bounds, scaling characteristics.

Specifically:

- **Synthesis cost scaling**. `lines.slice(-200)` caps observation count, but each line can be ~2000 chars (user prompts) or ~800 chars (tool calls). Worst case the prompt is ~400-500KB per backend call, sent 3x (psychologist, sociologist, merge). Reasonable?
- **Token cost on Claude backend**. Three sequential calls, each 3-4K output tokens. The synthesize_essence tool's response could exceed Claude Code's per-tool-response budget on a long enough session.
- **Lock-file race in the PreCompact script**. The `touch $LOCK_FILE` + check-then-touch pattern isn't atomic. Two simultaneous PreCompact firings can race.
- **`wc -l` on observations.jsonl every PreCompact**. Cheap on small files; degrades if archive isn't pruned and operators repoint at the archive accidentally.
- **No backoff or retry**. If the Anthropic API is rate-limited or transiently fails, what happens? `claudeChat()` propagates the error to the tool response.
- **The Ollama path has a 10-minute timeout**. On smaller hardware, `qwq:32b` synthesis can exceed this and hard-fail mid-merge, losing the prior two passes' work.

## Deliverables per reviewer

Each reviewer writes to `.tribunal/reports/P-session-essence-audit/reviewer-{arch,sec,perf}.md` with:

- A verdict line: `VERDICT: Approve | Request Changes | Escalate`
- A reasoning paragraph
- Numbered findings (each with severity ∈ {critical, warning, suggestion}, scenario, suggested defense)
- Cross-reviewer notes (things the reviewer suspects but knows are another lens's primary concern)

## Adversary

Once the three Approve, the adversary stage dispatches. For this audit the adversary should treat the lens reports as a starting point — surface what the trio missed.

## Output orchestration (this run)

The lens trio dispatches via three parallel `Task` calls with the reviewer agent markdown as the prompt body and the project directory as the working context. Reviewer reports land at `.tribunal/reports/P-session-essence-audit/reviewer-{arch,sec,perf}.md`. After all three return, the adversary dispatches. After the adversary returns, the synthesis lands at `.tribunal/reports/P-session-essence-audit/SYNTHESIS.md`. Final ledger flush via `tribunal-batch-file`.
