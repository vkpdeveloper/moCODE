import type { JsonObject, JsonValue, SessionEntrySnapshot } from "./types";

type UnknownRecord = Record<string, unknown>;

export type DerivedTodo = {
  id: string;
  content: string;
  status: string;
  priority: string;
};

export type DerivedFileDiff = {
  file: string;
  before: string;
  after: string;
  additions: number;
  deletions: number;
  status?: string;
};

function asObject(value: unknown): UnknownRecord | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as UnknownRecord;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function trimGitPath(value: string | null) {
  if (!value || value === "/dev/null") {
    return "";
  }
  if (value.startsWith("a/") || value.startsWith("b/")) {
    return value.slice(2);
  }
  return value;
}

function finalizeDiff(
  current: {
    file: string;
    before: string;
    after: string;
    additions: number;
    deletions: number;
    status?: string;
  } | null,
) {
  if (!current) {
    return null;
  }
  const file = current.after || current.file || current.before;
  if (!file) {
    return null;
  }
  return {
    file,
    before: current.before || current.file || file,
    after: current.after || current.file || file,
    additions: current.additions,
    deletions: current.deletions,
    ...(current.status ? { status: current.status } : {}),
  } satisfies DerivedFileDiff;
}

export function normalizeFileDiff(value: unknown): DerivedFileDiff | null {
  const diff = asObject(value);
  if (!diff) {
    return null;
  }
  const file = asString(diff.file) ?? "";
  const before = asString(diff.before) ?? file;
  const after = asString(diff.after) ?? file;
  if (!file && !before && !after) {
    return null;
  }
  return {
    file: file || after || before,
    before,
    after,
    additions: asNumber(diff.additions) ?? 0,
    deletions: asNumber(diff.deletions) ?? 0,
    ...(asString(diff.status) ? { status: asString(diff.status) ?? undefined } : {}),
  };
}

export function parseUnifiedDiff(diffText: string): DerivedFileDiff[] {
  if (!diffText.trim()) {
    return [];
  }

  const results: DerivedFileDiff[] = [];
  const lines = diffText.split(/\r?\n/);
  let current: {
    file: string;
    before: string;
    after: string;
    additions: number;
    deletions: number;
    status?: string;
  } | null = null;

  for (const line of lines) {
    if (line.startsWith("diff --git ")) {
      const finalized = finalizeDiff(current);
      if (finalized) {
        results.push(finalized);
      }

      const match = line.match(/^diff --git a\/(.+?) b\/(.+)$/);
      current = {
        file: match?.[2] ?? "",
        before: match?.[1] ?? "",
        after: match?.[2] ?? "",
        additions: 0,
        deletions: 0,
        status: "modified",
      };
      continue;
    }

    if (!current) {
      continue;
    }

    if (line.startsWith("new file mode ")) {
      current.status = "added";
      continue;
    }

    if (line.startsWith("deleted file mode ")) {
      current.status = "deleted";
      continue;
    }

    if (line.startsWith("rename from ")) {
      current.before = line.slice("rename from ".length).trim();
      continue;
    }

    if (line.startsWith("rename to ")) {
      current.after = line.slice("rename to ".length).trim();
      current.file = current.after;
      continue;
    }

    if (line.startsWith("--- ")) {
      current.before = trimGitPath(line.slice(4).trim());
      if (!current.before) {
        current.status = "added";
      }
      continue;
    }

    if (line.startsWith("+++ ")) {
      current.after = trimGitPath(line.slice(4).trim());
      current.file = current.after || current.before || current.file;
      if (!current.after) {
        current.status = "deleted";
      }
      continue;
    }

    if (line.startsWith("@@")) {
      continue;
    }

    if (line.startsWith("+") && !line.startsWith("+++")) {
      current.additions += 1;
      continue;
    }

    if (line.startsWith("-") && !line.startsWith("---")) {
      current.deletions += 1;
    }
  }

  const finalized = finalizeDiff(current);
  if (finalized) {
    results.push(finalized);
  }
  return results;
}

export function buildSessionDiffEntry(
  diffs: DerivedFileDiff[],
  rawDiff?: string | null,
): JsonObject {
  return {
    kind: "session_diff_update",
    update: {
      diff: diffs.map((diff) => ({ ...diff })),
      ...(rawDiff && rawDiff.trim().length > 0 ? { rawDiff } : {}),
    },
  };
}

export function todosFromPlanPayload(payload: JsonValue): DerivedTodo[] {
  const object = asObject(payload);
  const update =
    asObject(object?.update) ??
    (object && object.kind === "plan" ? object : null);
  const entries = asArray(update?.entries);
  return entries
    .map((entry, index) => {
      const item = asObject(entry);
      if (!item) {
        return null;
      }
      const content = asString(item.content)?.trim() ?? "";
      if (!content) {
        return null;
      }
      return {
        id: `${index}:${content}`,
        content,
        status: asString(item.status) ?? "pending",
        priority: asString(item.priority) ?? "normal",
      } satisfies DerivedTodo;
    })
    .filter((item): item is DerivedTodo => item !== null);
}

export function diffsFromSessionDiffPayload(payload: JsonValue): DerivedFileDiff[] {
  const object = asObject(payload);
  const update =
    asObject(object?.update) ??
    (object && object.kind === "session_diff_update" ? object : null);
  return asArray(update?.diff)
    .map(normalizeFileDiff)
    .filter((diff): diff is DerivedFileDiff => diff !== null);
}

export function latestTodosFromEntries(entries: SessionEntrySnapshot[]): DerivedTodo[] {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (entry?.kind !== "plan") {
      continue;
    }
    return todosFromPlanPayload(entry.payload);
  }
  return [];
}

export function latestDiffsFromEntries(entries: SessionEntrySnapshot[]): DerivedFileDiff[] {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (entry?.kind !== "session_diff_update") {
      continue;
    }
    return diffsFromSessionDiffPayload(entry.payload);
  }
  return [];
}
