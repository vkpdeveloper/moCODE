import { describe, expect, test } from "bun:test";

import { buildAgentInventory } from "./agent-inventory";

describe("buildAgentInventory", () => {
  test("shows only managed ACP agents in installed and uninstallable lists", () => {
    const inventory = buildAgentInventory({
      descriptors: [
        {
          id: "cursor",
          name: "Cursor",
          source: "acp",
          installState: "configured",
          binaryPath: "/tmp/cursor",
          metadata: {},
        },
        {
          id: "opencode",
          name: "OpenCode",
          source: "acp",
          installState: "detected",
          binaryPath: "/usr/local/bin/opencode",
          metadata: {},
        },
      ],
      registryAgents: [
        { id: "cursor", name: "Cursor Agent" },
        { id: "opencode", name: "OpenCode" },
      ],
    });

    expect(inventory.installed).toEqual([{ id: "cursor", name: "Cursor Agent" }]);
    expect(inventory.uninstallable).toEqual([{ id: "cursor", name: "Cursor Agent" }]);
  });

  test("shows only not-yet-installed registry agents in installable list", () => {
    const inventory = buildAgentInventory({
      descriptors: [
        {
          id: "cursor",
          name: "Cursor",
          source: "acp",
          installState: "configured",
          binaryPath: "/tmp/cursor",
          metadata: {},
        },
        {
          id: "opencode",
          name: "OpenCode",
          source: "acp",
          installState: "detected",
          binaryPath: "/usr/local/bin/opencode",
          metadata: {},
        },
      ],
      registryAgents: [
        { id: "cursor", name: "Cursor Agent" },
        { id: "opencode", name: "OpenCode" },
        { id: "claude-acp", name: "Claude" },
      ],
    });

    expect(inventory.installable).toEqual([{ id: "claude-acp", name: "Claude" }]);
  });

  test("returns no installable agents when registry is unavailable", () => {
    const inventory = buildAgentInventory({
      descriptors: [],
      registryAgents: [],
      registryAvailable: false,
    });

    expect(inventory.installable).toEqual([]);
  });
});
