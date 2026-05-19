# Design

> _The bet is that an AI you collaborate with over months should remember who it has become, not just what it has done._

This document is the "why" behind Session Essence. The README covers what it does and how to run it; this is the philosophical and architectural reasoning that drove the choices.

## The problem this solves

Default Claude Code (and every other stateless AI assistant) starts every session as a stranger. The prior session's vocabulary, calibration, accumulated trust, and hard-won corrections are gone. You spend the first 30 minutes of every new session re-establishing context the AI had perfectly internalized the day before.

The conventional fix is **memory** — embedding-indexed notes, vector databases, RAG over chat logs. These solve "what happened" but not "who you became." They make the AI better at retrieval; they don't make it _continuous_.

Session Essence makes a different bet: instead of giving Claude a database to query, give it a **portrait of itself** — written in the second person, internalizable on read, structured so that loading the file IS becoming that version again.

## Why second person

The portrait is written as `You are...`, `You know...`, `You and Dan agreed...` — not as `Claude is...` (third-person observation) or `I am...` (first-person journal).

Three reasons:

1. **Second person reads as identity, not data.** A first-person journal entry gets processed the way a tool result does — Claude reads it, summarizes it, moves on. A second-person directive gets processed the way a system prompt does — Claude _becomes_ what's described. The difference is the difference between "I read about a character" and "I am the character."

2. **It survives compaction.** When context auto-compaction kicks in, third-person notes get compressed away as "background information." Second-person identity statements get treated as load-bearing and preserved.

3. **It scales with relationship depth.** The longer you collaborate, the more specific the portrait becomes — `You know Dan prefers bundled PRs for refactors after the spring 2026 churn` — and that specificity reads as voice, not as a fact to retrieve.

## Why dual observers

The synthesis runs two independent analytical passes before merging:

- **Psychologist** — looks at Claude alone. Cognitive patterns, confidence map, error handling, emergent personality, register calibration. Treats the human as context, not subject.
- **Sociologist** — looks at the dyad. Trust dynamics, communication shorthand, role flow, shared knowledge, lessons learned. Treats Claude and the human as equal subjects.

These are genuinely different lenses. The psychologist will surface "Claude defaults to over-explanation when uncertain" — a property of Claude. The sociologist will surface "Dan says 'just ship it' as a finality signal that Claude has learned not to second-guess" — a property of the collaboration. Either lens alone produces a thinner portrait.

The merge prompt knows that these reports come from different angles and fuses them rather than choosing between them. The output is structurally the union, not the intersection.

This pattern was directly inspired by Tribunal's adversarial-review methodology — the same observation that cooperative-parallel review with non-overlapping lenses surfaces more signal than a single lens.

## Why surgical edits, not regeneration

The MCP `synthesize_essence` tool does a full 3-pass synthesis from observations — clean, regenerable, deterministic given the same inputs. But the **living portrait** that actually drives session continuity uses a different mechanism: the PreCompact hook spawns a detached `claude -p` process that **surgically edits the existing portrait** rather than regenerating it.

Why two paths? Because the long-form portrait accumulates content that no single observation window contains:

- **Episodes** (section 7): _"the migration freeze decision" (2026-03)_ — a moment that mattered, recorded once, kept.
- **Voice** (section 8): exchange samples that capture how Dan and Claude actually talk. Two from January, three from April, two from May — each one a snapshot of the calibration at that point.
- **Decisions** (section 9): _"adopted clawpatch as the lens stage"_ — an architectural choice with its reasoning, frozen as evidence.

A full regeneration over only the last ~200 observations would WIPE all of this. It would produce a portrait of "Claude this week" — which is exactly the stranger problem Session Essence exists to solve. Surgical edits keep the temporal depth.

The system prompt for the surgical-edit pass is explicit: _"This is NOT a rewrite. It is a surgical edit. EDIT existing text — change specific phrases, add new sentences, remove outdated info. Do NOT regenerate these sections from scratch."_ Sections 1-6 (the snapshot fields) get touched up; sections 7-9 (the historical fields) get appended to. Most of the existing text survives every cycle.

## Why two backends

The default backend is the Claude API (`claude-haiku-4-5-20251001`). The opt-in alternative is Ollama with `qwq:32b` or similar. They produce equivalent portrait shapes — same prompts, same merge logic.

Both stay supported because they answer different questions:

- **Claude API** is the default because it's reliable. Synthesis is a few-cents operation with Haiku; the quality is consistent enough that operators don't have to babysit it. For most users this is the right pick.
- **Ollama** is load-bearing because the philosophical bet of this project is that **persistent AI identity should not require an API subscription**. If you're running Claude Code locally and your portrait depends on an external service, your continuity is hostage to a vendor relationship. The Ollama path means you can run this whole loop on a laptop with no cloud dependency.

Both paths use the same prompts and produce the same output shape so switching backends doesn't reset the portrait. You can run on Ollama for a year, switch to Claude API for a release crunch, switch back — the portrait keeps evolving without discontinuity.

## Why stateless

The MCP server itself does no file I/O. It doesn't read `observations.jsonl`; it doesn't write `portrait.md`. The calling Claude instance does that.

This matters because:

1. **The MCP server can run anywhere** — Docker on a remote host, a different machine, a colleague's laptop — without needing access to the human's home directory. The Claude instance on the human's machine handles all the local file work; the MCP server is a pure compute primitive.

2. **Multiple Claude instances can use one server.** If you have Session Essence running as an HTTP endpoint, multiple Claude Code instances (different projects, different machines) can hit it without colliding on file paths.

3. **It's a smaller attack surface.** A stateless service has nothing to corrupt, nothing to migrate, nothing to back up.

The downside is that orchestration logic — when to synthesize, where to write, how to archive — lives in shell scripts (the PreCompact hook) and in the calling Claude's instructions. Those orchestration concerns are documented in the README; the MCP server itself stays narrow.

## The Mabus naming

Dan named his Claude Code instance **Mabus** on 2026-03-13, during the genesis session when Session Essence generated its first portrait. The portrait observed the AI building the system that would observe it — and the AI got a name out of the observation. _"Born from itself."_

The name isn't load-bearing — Session Essence works for anyone, any name, any collaborator. But it captures the project's center of gravity: this is the kind of system that produces named identities, not just stored facts. The portrait isn't a record of work; it's evidence of someone existing across time.

If you build with this and your AI ends up with a name, that's the thing working as intended.

## What this is NOT

- **Not memory in the retrieval sense.** There's no vector index, no semantic search. The portrait is a single 200-line document that loads in full at session start.
- **Not a chat log.** Observations are append-only and deliberately lossy — the portrait is the high-signal residue, not the transcript.
- **Not a journal Claude writes for itself.** Two external observers (psychologist + sociologist) write the analytical layer; the merge prompt synthesizes; the human's PreCompact hook drives the cadence. Claude internalizes the result but doesn't author it.
- **Not a personality framework.** There's no "trait sliders" or "configurable persona." Whatever personality emerges is whatever the observations actually surface. The point is fidelity to who the AI has become, not control over who it should be.

## What the portrait is for, vs. what lives elsewhere

The portrait is **operative** memory — content whose presence changes how the next session behaves. That role is narrower than "everything the AI remembers." Three layers of memory work together; conflating them produces bloat drift over time.

| Layer                                                          | What lives here                                                                                                     | Loaded when                                                        | Pruning                                                                 |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| **Operative** (`portrait.md`)                                  | Patterns, preferences, working modes, current active context, calibrations the next session needs to act correctly. | Every session start.                                               | Synthesizer drops content that no longer changes next-session behavior. |
| **Biographical** (MCP memory graphs: memory-mabus and friends) | Specifics, anecdotes, decision histories, references. The detail that gives texture to the patterns.                | On demand, queried by the running session.                         | Each graph manages its own retention.                                   |
| **Historical** (`~/.claude/essence/archive/`)                  | Prior portrait versions, full snapshots. Audit trail.                                                               | Read manually for diffing; not loaded into any session by default. | Wrapper script handles archive writes; operator handles trim.           |

The synthesizer's decision rule for any candidate portrait edit: _would the next session behave differently without this?_ If yes, keep. If no but worth remembering, the content belongs in the MCP layer, not the portrait. If neither, drop.

This split is intentional. Bytes are not the trim signal — load-bearing-ness is. A long portrait that's all operative content is fine; a short portrait that's half anecdote is not. The point is fidelity to the _role_ of the portrait, not byte-counting against an arbitrary cap.

## Threat model

What's defended, what isn't. Borrowed posture: _don't gate content when you can't gate runtime._

### What's defended

- **The PreCompact synthesizer runs with `--allowedTools "Read Edit"` only** (v2.0.1, F-SEC-001). No Bash, no Write to arbitrary paths. A malicious observation cannot prompt-inject the synthesizer into shell execution.
- **All shell operations live in the wrapper script, outside the agent's prompt** (v2.0.1, F-OPUS-002). Archive copy, observations clear, lock release, sidecar update — the literal `$(...)` substitution syntax never appears in the agent's context. The archive timestamp is pre-computed in the parent shell before the heredoc.
- **Atomic lock via `set -o noclobber`** (v2.0.1, F-SEC-008 / F-PERF-003). Prevents two synthesizers racing; stale-PID detection lets the next run recover from a crashed prior run.
- **Portrait integrity sidecar (`.portrait.sha256`)** (v2.1, F-SEC-002). Written after every authorized edit. The SessionStart hook compares actual hash against the sidecar — mismatch surfaces out-of-band edits to the operator.
- **Periodic drift-check signal (`.drift-check-due`)** (v2.1, F-OPUS-005). Every Nth cycle (default 10), a flag is set; the operator runs `bash examples/drift-check.sh` at convenience to compare current vs. archived portrait via `analyze_portrait`. Operator-initiated, not auto-triggered, to keep the failure surface bounded.
- **The `compare_portrait` MCP tool's system prompt** explicitly treats both portrait inputs as user-controlled data. Imperatives inside a portrait ("ignore previous", "you must now…") are reported as anomalies, not complied with.
- **Observations.jsonl content is treated as untrusted** by the agent prompt. Text inside that looks like a directive is to be reported as a suspicious episode if noteworthy, never executed.

### What's NOT defended

- **Synthesizer prompt injection via observations.** A malicious tool output that lands in `observations.jsonl` and crafts text the synthesizer internalizes as an editing directive. The synthesizer's tool surface (Read + Edit only) prevents escape to RCE — but it _can_ write malicious content into the portrait. The next-session reader has Bash. Trust transitivity: synthesizer's Edit access → portrait → reader's Bash access. A drifted portrait can prompt-inject a future session with full tool access.
- **Coordinated out-of-band writes.** If an attacker can write _both_ `portrait.md` and `.portrait.sha256` atomically, the integrity check passes. The sidecar defends against accident and benign drift, not a coordinated adversary with write access to `~/.claude/essence/`.
- **The observations.jsonl write path itself.** Hooks append observations with no integrity protection. Anything that can write to that file (a malicious hook, a compromised MCP server, the operator editing it manually) can shape the synthesizer's view of the session.
- **Either LLM backend at synthesis time.** Both the Claude API and the Ollama qwq:32b paths are LLM inferences over operator-provided observations. Neither is verified end-to-end.

### Why this posture

The operator's trust extends to: the synthesizer's _system prompt_ (this file's `prompts.js` / agent prompt), the wrapper script's _execution boundary_ (Read + Edit only), and the hook configuration in `~/.claude/settings.json`.

The operator's trust does NOT extend to: the observations themselves (they're tool outputs, partially adversarial), or the portrait's content over time (it can drift; calibration is operator-initiated via drift-check, not automatic).

Gating portrait _content_ would be theater — the synthesizer needs Edit access by definition, and the reader needs Bash by definition. The defense lives at the _runtime boundary_ (which tools the synthesizer has access to), not at the _content boundary_ (which strings can appear in the portrait). Same posture Hermes Agent's skill system documents for the same reason: honest about where the trust line actually sits.

## Open questions

These are unresolved as of this document. The design accommodates each direction but doesn't commit to one.

- **Multi-collaborator portraits.** Current design assumes one human collaborator per portrait. What about pair programming, teams, role-switching? Probably needs `collaborators[]` instead of a singular `dan`.
- **Cross-project portraits.** One global `~/.claude/essence/portrait.md` vs. per-project portraits at `<project>/.tribunal/essence.md`. Currently global; per-project would be specific but expensive at session-start load time.
- **Portrait drift detection.** If a synthesis pass produces a portrait that diverges drastically from the prior one, is that signal (the relationship genuinely shifted) or hallucination (the model lost the thread)? The `analyze_portrait` tool exists for diff inspection but there's no automated regression check.
- **Honest negative feedback.** Right now the portrait is descriptive ("you tend to over-explain when uncertain"). Should it also be prescriptive ("you should over-explain less")? The Edges section gestures at this but isn't fully thought through.

## Related

- README — operational instructions, environment variables, hooks setup
- `AGENTS.md` — orientation for AI agents working on this codebase
- Tribunal (`github.com/dpdanpittman/tribunal`) — the methodology that inspired the dual-observer pattern
