import { describe, expect, test } from "bun:test";

import { isSupportedAgentId } from "./agents";

describe("isSupportedAgentId", () => {
  test("accepts the curated agent ids", () => {
    expect(isSupportedAgentId("amp-acp")).toBe(true);
    expect(isSupportedAgentId("claude-acp")).toBe(true);
    expect(isSupportedAgentId("codex-acp")).toBe(true);
    expect(isSupportedAgentId("cursor")).toBe(true);
    expect(isSupportedAgentId("gemini")).toBe(true);
    expect(isSupportedAgentId("github-copilot-cli")).toBe(true);
    expect(isSupportedAgentId("kilo")).toBe(true);
    expect(isSupportedAgentId("opencode")).toBe(true);
  });

  test("rejects agents outside the curated list", () => {
    expect(isSupportedAgentId("qwen-code")).toBe(false);
    expect(isSupportedAgentId("goose")).toBe(false);
    expect(isSupportedAgentId("openai-agents")).toBe(false);
  });
});
