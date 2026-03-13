#!/usr/bin/env node
// =============================================================================
// MCP Server: Session Essence
// =============================================================================
// Synthesizes AI session portraits using dual-observer analysis via Ollama.
// Two analytical lenses (psychologist + sociologist) independently analyze
// interaction logs, then a merge prompt fuses them into a second-person
// portrait that Claude can internalize at session start.
//
// Designed to run standalone (stdio) or via supergateway (HTTP).
// Stateless — all file I/O is handled by the calling Claude instance.
// =============================================================================

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import {
  PSYCHOLOGIST_SYSTEM,
  SOCIOLOGIST_SYSTEM,
  MERGE_SYSTEM,
} from "./prompts.js";

const OLLAMA_HOST = process.env.OLLAMA_HOST || "http://localhost:11434";
const OLLAMA_MODEL = process.env.OLLAMA_MODEL || "qwq:32b";
const OLLAMA_TIMEOUT = parseInt(process.env.OLLAMA_TIMEOUT || "600000", 10); // 10 min default

// -----------------------------------------------------------------------------
// Ollama API helper
// -----------------------------------------------------------------------------

async function ollamaChat(messages, options = {}) {
  const body = {
    model: options.model || OLLAMA_MODEL,
    messages,
    stream: false,
    options: {
      temperature: options.temperature ?? 0.6,
      num_predict: options.maxTokens ?? 4096,
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OLLAMA_TIMEOUT);

  try {
    const res = await fetch(`${OLLAMA_HOST}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "unknown error");
      throw new Error(`Ollama API error ${res.status}: ${text}`);
    }

    const data = await res.json();
    return {
      content: data.message?.content || "",
      model: data.model,
      totalDuration: data.total_duration,
      evalCount: data.eval_count,
    };
  } finally {
    clearTimeout(timeout);
  }
}

// -----------------------------------------------------------------------------
// MCP Server setup
// -----------------------------------------------------------------------------

const server = new McpServer({
  name: "session-essence",
  version: "1.0.0",
});

// ---------------------------------------------------------------------------
// Tool 1: synthesize_essence
// ---------------------------------------------------------------------------

server.tool(
  "synthesize_essence",
  `Synthesize a session portrait from interaction observations. Runs three
sequential Ollama analyses: (1) psychologist profile of Claude's cognitive
patterns, (2) sociologist report on the collaborative dynamic, (3) merged
second-person portrait. The portrait captures personality + understanding +
relationship so Claude can become that version of itself at session start.

Pass the contents of observations.jsonl as the observations parameter.
Optionally pass the previous portrait for continuity.`,
  {
    observations: z
      .string()
      .describe(
        "The interaction observations as text (contents of observations.jsonl)",
      ),
    previous_portrait: z
      .string()
      .optional()
      .describe(
        "The previous portrait text, if any, for continuity across syntheses",
      ),
  },
  async ({ observations, previous_portrait }) => {
    const lines = observations.trim().split("\n");
    if (lines.length < 10) {
      return {
        content: [
          {
            type: "text",
            text: `Insufficient observations (${lines.length} < 10 minimum). Continue the session and try again later.`,
          },
        ],
      };
    }

    // Truncate to last 200 observations to fit context window
    const truncated = lines.slice(-200).join("\n");
    const logPreamble = previous_portrait
      ? `Previous portrait (for continuity):\n${previous_portrait}\n\n---\n\nNew interaction log:\n`
      : "Interaction log:\n";
    const logText = logPreamble + truncated;

    try {
      // Phase 1: Psychologist analysis
      const psychResult = await ollamaChat(
        [
          { role: "system", content: PSYCHOLOGIST_SYSTEM },
          { role: "user", content: logText },
        ],
        { temperature: 0.5, maxTokens: 3000 },
      );

      // Phase 2: Sociologist analysis
      const socioResult = await ollamaChat(
        [
          { role: "system", content: SOCIOLOGIST_SYSTEM },
          { role: "user", content: logText },
        ],
        { temperature: 0.5, maxTokens: 3000 },
      );

      // Phase 3: Merge into portrait
      const mergeInput = `Report A (Psychologist — Claude's cognitive patterns):\n\n${psychResult.content}\n\n---\n\nReport B (Sociologist — interaction dynamics):\n\n${socioResult.content}`;
      const mergeResult = await ollamaChat(
        [
          { role: "system", content: MERGE_SYSTEM },
          { role: "user", content: mergeInput },
        ],
        { temperature: 0.6, maxTokens: 2000 },
      );

      const totalTokens =
        (psychResult.evalCount || 0) +
        (socioResult.evalCount || 0) +
        (mergeResult.evalCount || 0);
      const totalTime =
        ((psychResult.totalDuration || 0) +
          (socioResult.totalDuration || 0) +
          (mergeResult.totalDuration || 0)) /
        1e9;

      const output = [
        "# Session Essence Portrait",
        "",
        mergeResult.content,
        "",
        "---",
        "",
        "<details>",
        "<summary>Analysis Details</summary>",
        "",
        "## Psychologist Report",
        "",
        psychResult.content,
        "",
        "## Sociologist Report",
        "",
        socioResult.content,
        "",
        `_Model: ${mergeResult.model} | Total tokens: ${totalTokens} | Time: ${totalTime.toFixed(1)}s | Observations analyzed: ${lines.length}_`,
        "</details>",
      ].join("\n");

      return {
        content: [{ type: "text", text: output }],
      };
    } catch (err) {
      return {
        content: [
          {
            type: "text",
            text: `Synthesis error: ${err.message}`,
          },
        ],
        isError: true,
      };
    }
  },
);

// ---------------------------------------------------------------------------
// Tool 2: format_observation
// ---------------------------------------------------------------------------

server.tool(
  "format_observation",
  `Format a manual observation as a JSONL line for appending to the observations
log. Use this when you notice something the hooks wouldn't capture — a shift
in tone, an important realization, a moment of particularly good or bad
collaboration.`,
  {
    category: z
      .enum([
        "personality",
        "communication",
        "trust",
        "correction",
        "insight",
        "context",
      ])
      .describe("What kind of observation this is"),
    note: z
      .string()
      .describe(
        "The observation content — be specific and cite what prompted it",
      ),
  },
  async ({ category, note }) => {
    const entry = {
      ts: new Date().toISOString(),
      e: "manual",
      d: { category, note },
    };
    return {
      content: [{ type: "text", text: JSON.stringify(entry) }],
    };
  },
);

// ---------------------------------------------------------------------------
// Tool 3: analyze_portrait
// ---------------------------------------------------------------------------

server.tool(
  "analyze_portrait",
  `Compare two portraits to identify what changed — useful for understanding
how the session relationship evolved between syntheses.`,
  {
    old_portrait: z.string().describe("The earlier portrait text"),
    new_portrait: z.string().describe("The more recent portrait text"),
  },
  async ({ old_portrait, new_portrait }) => {
    try {
      const result = await ollamaChat(
        [
          {
            role: "system",
            content: `You are comparing two session portraits of an AI assistant. Identify what changed between them. Focus on: shifts in personality/voice, changes in trust level, new lessons learned, communication calibration changes, and work context changes. Be concise and specific.`,
          },
          {
            role: "user",
            content: `EARLIER PORTRAIT:\n${old_portrait}\n\n---\n\nLATER PORTRAIT:\n${new_portrait}`,
          },
        ],
        { temperature: 0.4, maxTokens: 2000 },
      );

      return {
        content: [{ type: "text", text: result.content }],
      };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Analysis error: ${err.message}` }],
        isError: true,
      };
    }
  },
);

// -----------------------------------------------------------------------------
// Start
// -----------------------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
