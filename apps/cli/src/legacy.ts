import type {
  JsonObject,
  JsonValue,
  ProjectRecord,
  SessionRecord,
  SessionSnapshot,
} from "./types";

function isoToMillis(value: string | null | undefined) {
  if (!value) {
    return Date.now();
  }
  const millis = new Date(value).getTime();
  return Number.isNaN(millis) ? Date.now() : millis;
}

function asObject(value: JsonValue | undefined): JsonObject | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as JsonObject;
}

function asString(value: JsonValue | undefined): string | null {
  return typeof value === "string" ? value : null;
}

function extractTextContent(content: JsonValue | undefined): string {
  const object = asObject(content);
  if (!object) {
    return "";
  }
  if (object.type === "text" && typeof object.text === "string") {
    return object.text;
  }
  if (object.type === "resource_link") {
    const title = asString(object.title);
    const uri = asString(object.uri);
    return [title, uri].filter(Boolean).join(" ").trim();
  }
  return "";
}

function stringifyValue(value: JsonValue | undefined) {
  if (value === undefined || value === null) {
    return "";
  }
  if (typeof value === "string") {
    return value;
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function toolStatus(status: JsonValue | undefined) {
  switch (status) {
    case "in_progress":
      return "running";
    case "failed":
      return "error";
    case "completed":
    case "pending":
      return status;
    default:
      return "pending";
  }
}

function toolName(kind: JsonValue | undefined, title: JsonValue | undefined) {
  if (typeof title === "string" && title.trim().length > 0) {
    return title.trim().toLowerCase().replace(/\s+/g, "_");
  }
  if (typeof kind === "string" && kind.trim().length > 0) {
    return kind;
  }
  return "tool";
}

export function serializeLegacyProject(project: ProjectRecord): JsonObject {
  return {
    id: project.id,
    worktree: project.rootPath,
    vcs: "git",
    name: project.displayName ?? project.detectedName,
    time: {
      created: isoToMillis(project.createdAt),
      updated: isoToMillis(project.updatedAt),
      initialized: isoToMillis(project.lastOpenedAt ?? project.updatedAt),
    },
    sandboxes: [],
  };
}

export function serializeLegacySession(session: SessionRecord): JsonObject {
  return {
    id: session.id,
    slug: session.id.slice(0, 8),
    projectID: session.projectId,
    agentID: session.agentId,
    directory: session.cwd,
    title: session.title ?? "New Session",
    version: "acp",
    time: {
      created: isoToMillis(session.createdAt),
      updated: isoToMillis(session.updatedAt),
    },
  };
}

type LegacyMessage = {
  info: JsonObject;
  parts: JsonObject[];
};

type AssistantBuilder = LegacyMessage & {
  partIndexByKey: Map<string, number>;
};

function createUserMessage(
  session: SessionRecord,
  entryId: string,
  text: string,
  createdAt: string,
  currentMode: string,
): LegacyMessage {
  const created = isoToMillis(createdAt);
  return {
    info: {
      id: entryId,
      sessionID: session.id,
      role: "user",
      agent: currentMode,
      time: {
        created,
        completed: created,
      },
    },
    parts: [
      {
        id: `${entryId}:text`,
        sessionID: session.id,
        messageID: entryId,
        type: "text",
        text,
        synthetic: false,
        time: {
          start: created,
          end: created,
        },
      },
    ],
  };
}

function createAssistantMessage(
  session: SessionRecord,
  messageId: string,
  createdAt: string,
  currentMode: string,
  parentId: string | null,
): AssistantBuilder {
  const created = isoToMillis(createdAt);
  return {
    info: {
      id: messageId,
      sessionID: session.id,
      role: "assistant",
      parentID: parentId,
      modelID: "default",
      providerID: "local",
      mode: currentMode,
      agent: session.agentId,
      path: {
        cwd: session.cwd,
        root: session.cwd,
      },
      cost: 0,
      tokens: {
        input: 0,
        output: 0,
        reasoning: 0,
        cache: {
          read: 0,
          write: 0,
        },
      },
      time: {
        created,
      },
    },
    parts: [],
    partIndexByKey: new Map<string, number>(),
  };
}

function appendOrMergeTextPart(
  builder: AssistantBuilder,
  partType: "text" | "reasoning",
  delta: string,
  createdAt: string,
) {
  const key = partType;
  const index = builder.partIndexByKey.get(key);
  const created = isoToMillis(createdAt);
  if (index === undefined) {
    const id = `${builder.info.id}:${partType}`;
    builder.parts.push({
      id,
      sessionID: builder.info.sessionID,
      messageID: builder.info.id,
      type: partType,
      text: delta,
      time: {
        start: created,
        end: created,
      },
    });
    builder.partIndexByKey.set(key, builder.parts.length - 1);
    return;
  }

  const current = builder.parts[index]!;
  const existingText = asString(current.text) ?? "";
  current.text = `${existingText}${delta}`;
  current.time = {
    start: asObject(current.time)?.start ?? created,
    end: created,
  };
}

function upsertToolPart(
  builder: AssistantBuilder,
  entryId: string,
  toolCallId: string,
  value: JsonObject,
) {
  const key = `tool:${toolCallId}`;
  const nextState: JsonObject = {
    status: toolStatus(value.status),
  };
  if (value.rawInput !== undefined) {
    nextState.input =
      typeof value.rawInput === "object" && value.rawInput !== null
        ? value.rawInput
        : {
            raw: stringifyValue(value.rawInput),
          };
  }
  if (value.rawOutput !== undefined) {
    nextState.output = stringifyValue(value.rawOutput);
  }
  if (value.title !== undefined) {
    nextState.title = value.title;
  }
  if (value.locations !== undefined) {
    nextState.metadata = {
      locations: value.locations,
    };
  }

  const currentIndex = builder.partIndexByKey.get(key);
  if (currentIndex === undefined) {
    builder.parts.push({
      id: `${entryId}:tool:${toolCallId}`,
      sessionID: builder.info.sessionID,
      messageID: builder.info.id,
      type: "tool",
      callID: toolCallId,
      tool: toolName(value.kind, value.title),
      state: nextState,
    });
    builder.partIndexByKey.set(key, builder.parts.length - 1);
    return;
  }

  const current = builder.parts[currentIndex]!;
  const mergedState = {
    ...(asObject(current.state) ?? {}),
    ...nextState,
  };
  current.tool = toolName(value.kind ?? current.tool, value.title ?? current.tool);
  current.state = mergedState;
}

function upsertPlanPart(builder: AssistantBuilder, plan: JsonObject) {
  const entries = Array.isArray(plan.entries) ? plan.entries : [];
  const text = entries
    .map((entry) => {
      const item = asObject(entry as JsonValue);
      if (!item) {
        return null;
      }
      const status = asString(item.status) ?? "pending";
      const prefix = status === "completed" ? "[x]" : status === "in_progress" ? "[>]" : "[ ]";
      return `${prefix} ${asString(item.content) ?? ""}`.trim();
    })
    .filter((entry): entry is string => Boolean(entry))
    .join("\n");
  if (!text) {
    return;
  }

  const key = "plan";
  const currentIndex = builder.partIndexByKey.get(key);
  const part = {
    id: `${builder.info.id}:plan`,
    sessionID: builder.info.sessionID,
    messageID: builder.info.id,
    type: "reasoning",
    text,
  } satisfies JsonObject;
  if (currentIndex === undefined) {
    builder.parts.push(part);
    builder.partIndexByKey.set(key, builder.parts.length - 1);
    return;
  }
  builder.parts[currentIndex] = part;
}

export function buildLegacyMessages(snapshot: SessionSnapshot | null): JsonObject[] {
  if (!snapshot) {
    return [];
  }

  const messages: Array<LegacyMessage | AssistantBuilder> = [];
  let currentMode = "build";
  let currentAssistant: AssistantBuilder | null = null;
  let currentParentId: string | null = null;

  for (const entry of snapshot.entries) {
    const payload = asObject(entry.payload);
    if (!payload) {
      continue;
    }

    if (entry.kind === "current_mode_update") {
      const update = asObject(payload.update);
      const nextMode = asString(update?.currentModeId);
      if (nextMode) {
        currentMode = nextMode;
      }
      continue;
    }

    if (entry.kind === "session_info_update") {
      continue;
    }

    if (entry.kind === "user_message") {
      currentAssistant = null;
      currentParentId = entry.id;
      messages.push(
        createUserMessage(
          snapshot.session,
          entry.id,
          asString(payload.text) ?? "",
          entry.createdAt,
          currentMode,
        ),
      );
      continue;
    }

    const isAssistantEntry = new Set([
      "agent_message_chunk",
      "agent_thought_chunk",
      "tool_call",
      "tool_call_update",
      "plan",
    ]).has(entry.kind);
    if (!isAssistantEntry) {
      continue;
    }

    if (!currentAssistant) {
      currentAssistant = createAssistantMessage(
        snapshot.session,
        `assistant:${entry.id}`,
        entry.createdAt,
        currentMode,
        currentParentId,
      );
      messages.push(currentAssistant);
    }

    currentAssistant.info.mode = currentMode;
    currentAssistant.info.time = {
      ...(asObject(currentAssistant.info.time) ?? {}),
      completed: isoToMillis(entry.createdAt),
    };

    if (entry.kind === "agent_message_chunk") {
      appendOrMergeTextPart(
        currentAssistant,
        "text",
        extractTextContent(payload.content),
        entry.createdAt,
      );
      continue;
    }

    if (entry.kind === "agent_thought_chunk") {
      appendOrMergeTextPart(
        currentAssistant,
        "reasoning",
        extractTextContent(payload.content),
        entry.createdAt,
      );
      continue;
    }

    if (entry.kind === "tool_call" || entry.kind === "tool_call_update") {
      const update = asObject(payload.update) ?? payload;
      const toolCallId = asString(update.toolCallId);
      if (!toolCallId) {
        continue;
      }
      upsertToolPart(currentAssistant, entry.id, toolCallId, update);
      continue;
    }

    if (entry.kind === "plan") {
      const update = asObject(payload.update) ?? payload;
      upsertPlanPart(currentAssistant, update);
    }
  }

  return messages.map((message) => ({
    info: message.info,
    parts: message.parts,
  }));
}

export function findLegacyMessage(
  messages: JsonObject[],
  messageId: string,
): JsonObject | null {
  for (const message of messages) {
    if (message.info && asObject(message.info)?.id === messageId) {
      return message;
    }
  }
  return null;
}

export function latestLegacyMessageForEntry(
  snapshot: SessionSnapshot | null,
  entryKind: string,
  payload: JsonValue,
): { message: JsonObject; part: JsonObject | null; delta: string | null } | null {
  const messages = buildLegacyMessages(snapshot);
  if (messages.length === 0) {
    return null;
  }

  if (entryKind === "user_message") {
    const message = messages[messages.length - 1]!;
    const parts = Array.isArray(message.parts) ? message.parts : [];
    const part = parts.length > 0 ? (parts[parts.length - 1] as JsonObject) : null;
    return { message, part, delta: asString(asObject(payload)?.text) };
  }

  const assistant = [...messages]
    .reverse()
    .find((message) => asObject(message.info)?.role === "assistant");
  if (!assistant) {
    return null;
  }

  const parts = Array.isArray(assistant.parts)
    ? assistant.parts.map((part) => part as JsonObject)
    : [];

  if (entryKind === "agent_message_chunk") {
    const part = [...parts].reverse().find((item) => item.type === "text") ?? null;
    return {
      message: assistant,
      part,
      delta: extractTextContent(asObject(payload)?.content),
    };
  }

  if (entryKind === "agent_thought_chunk") {
    const part = [...parts].reverse().find((item) => item.type === "reasoning") ?? null;
    return {
      message: assistant,
      part,
      delta: extractTextContent(asObject(payload)?.content),
    };
  }

  if (entryKind === "tool_call" || entryKind === "tool_call_update") {
    const update = asObject(asObject(payload)?.update) ?? asObject(payload);
    const toolCallId = asString(update?.toolCallId);
    const part = toolCallId
      ? [...parts].reverse().find((item) => item.callID === toolCallId) ?? null
      : null;
    return {
      message: assistant,
      part,
      delta: null,
    };
  }

  if (entryKind === "plan") {
    const part =
      [...parts].reverse().find((item) => item.type === "reasoning") ?? null;
    return {
      message: assistant,
      part,
      delta: null,
    };
  }

  return {
    message: assistant,
    part: null,
    delta: null,
  };
}

export function serializeLegacyPermission(input: {
  id: string;
  sessionId: string;
  request: JsonObject;
}): JsonObject {
  const toolCall = asObject(input.request.toolCall);
  const options = Array.isArray(input.request.options)
    ? input.request.options
        .map((option) => asObject(option as JsonValue))
        .filter((option): option is JsonObject => option !== null)
    : [];
  return {
    id: input.id,
    sessionID: input.sessionId,
    permission: asString(toolCall?.title) ?? asString(toolCall?.kind) ?? "permission",
    patterns: options
      .map((option) => asString(option.name))
      .filter((option): option is string => Boolean(option)),
    metadata: {
      toolCall,
      options,
    },
    always: options
      .map((option) => asString(option.kind))
      .filter((option): option is string => option === "allow_always"),
    tool: {
      messageID: `assistant:${input.sessionId}`,
      callID: asString(toolCall?.toolCallId) ?? input.id,
    },
  };
}
