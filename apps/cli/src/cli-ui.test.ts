import { describe, expect, test } from "bun:test";

import { buildSelectOptions } from "./cli-ui";

describe("buildSelectOptions", () => {
  test("builds label-only options for the minimal CLI selector", () => {
    expect(
      buildSelectOptions([
        { id: "cursor", name: "Cursor" },
        { id: "claude-acp", name: "Claude" },
      ]),
    ).toEqual([
      { label: "Cursor", value: "cursor" },
      { label: "Claude", value: "claude-acp" },
    ]);
  });
});
