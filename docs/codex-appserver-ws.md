# Codex App Server — WebSocket / stdio Protocol Reference

> Source: [`openai/codex`](https://github.com/openai/codex) — `codex-rs/app-server`, `codex-rs/app-server-protocol`, `codex-rs/app-server-test-client`

---

## Table of Contents

1. [Overview](#overview)
2. [Transport Layer](#transport-layer)
3. [Wire Format — JSON-RPC 2.0](#wire-format--json-rpc-20)
4. [Connection Lifecycle](#connection-lifecycle)
5. [Client → Server Requests](#client--server-requests)
   - [Connection & Session Management](#connection--session-management)
   - [Thread Lifecycle (v2 / current)](#thread-lifecycle-v2--current)
   - [Turn Control](#turn-control)
   - [Models & Features](#models--features)
   - [Account & Auth](#account--auth)
   - [Configuration API](#configuration-api)
   - [MCP Servers](#mcp-servers)
   - [Skills & Apps](#skills--apps)
   - [File Search](#file-search)
   - [Utilities](#utilities)
   - [Realtime (Experimental)](#realtime-experimental)
   - [Deprecated v1 Methods](#deprecated-v1-methods)
6. [Server → Client Requests (Approval Callbacks)](#server--client-requests-approval-callbacks)
7. [Server → Client Notifications](#server--client-notifications)
8. [Client → Server Notifications](#client--server-notifications)
9. [Core Data Types](#core-data-types)
10. [Error Codes](#error-codes)
11. [Thread Status & Active Flags](#thread-status--active-flags)
12. [Approval & Sandbox Policies](#approval--sandbox-policies)
13. [Experimental API Flag](#experimental-api-flag)
14. [Environment Variables & Logging](#environment-variables--logging)
15. [Quick-Start Examples](#quick-start-examples)

---

## Overview

The **Codex App Server** is a long-running server process that powers rich clients like the VS Code extension. It wraps the Codex agent (LLM + tool execution engine) and exposes all functionality via **bidirectional JSON-RPC 2.0** over two transports:

| Transport | Format |
|-----------|--------|
| `stdio://` (default) | Newline-delimited JSON (JSONL) on stdin / stdout |
| `ws://IP:PORT` | WebSocket text frames (one JSON object per frame) |

The WebSocket transport is described as "experimental" in the source but is fully implemented. Binary frames are explicitly rejected with a warning.

---

## Transport Layer

### Starting with stdio (default)

```bash
codex app-server
# or
codex app-server --listen stdio://
```

Each message is a single JSON object terminated by a newline (`\n`). The server reads from stdin and writes to stdout.

### Starting with WebSocket

```bash
codex app-server --listen ws://127.0.0.1:4222
```

The server binds a TCP listener. On startup it prints a banner to **stderr**:

```
codex app-server (WebSockets)
  listening on: ws://127.0.0.1:4222
  note: binds localhost only (use SSH port-forwarding for remote access)
```

**Important constraints:**

- The listen URL **must** be `ws://IP:PORT` with a numeric IP — `localhost` is not accepted.
- The server only binds loopback by default; use SSH port-forwarding for remote access.
- Only **text frames** are supported. Binary frames are dropped with a warning.
- Ping frames are reflected back as Pong frames automatically.
- Multiple simultaneous connections are supported; each connection gets its own `ConnectionId`.

### Internal Channel Capacity

The server uses bounded async channels (`CHANNEL_CAPACITY = 128`). When the channel is full for a WebSocket connection, the server returns a JSON-RPC error (`-32001`, "Server overloaded; retry later") instead of blocking. For stdio, the server waits (blocks) rather than erroring.

Clients should handle `-32001` by retrying with **exponential backoff and jitter** rather than immediately resending.

### Schema Generation

TypeScript types and JSON Schema files can be generated directly from the Codex binary:

```bash
codex app-server generate-ts --out ./schemas
codex app-server generate-json-schema --out ./schemas
```

---

## Wire Format — JSON-RPC 2.0

All messages are JSON objects. The `jsonrpc` version field (`"2.0"`) is **not** transmitted on the wire to save bandwidth.

### Message Types

#### Client → Server Request
```json
{
  "method": "thread/start",
  "id": 1,
  "params": { ... }
}
```

#### Server → Client Response (success)
```json
{
  "id": 1,
  "result": { ... }
}
```

#### Server → Client Response (error)
```json
{
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Invalid params: ...",
    "data": null
  }
}
```

#### Server → Client Notification (no id, no reply expected)
```json
{
  "method": "thread/status/changed",
  "params": { ... }
}
```

#### Server → Client Request (server-initiated, requires client reply)
```json
{
  "method": "item/commandExecution/requestApproval",
  "id": "srv-req-42",
  "params": { ... }
}
```

The client must reply to server-initiated requests with a normal JSON-RPC response:
```json
{
  "id": "srv-req-42",
  "result": { "decision": "accept" }
}
```

### Request ID

`id` can be either a string or a 64-bit integer:

```typescript
type RequestId = string | number;
```

---

## Connection Lifecycle

### 1. Connect

Open a WebSocket connection (or start the process for stdio). No automatic handshake occurs.

### 2. Send `initialize`

The **first** message from the client must be an `initialize` request:

```json
{
  "method": "initialize",
  "id": 1,
  "params": {
    "clientInfo": {
      "name": "my-client",
      "title": "My Client Display Name",
      "version": "1.0.0"
    },
    "capabilities": {
      "experimentalApi": false,
      "optOutNotificationMethods": []
    }
  }
}
```

**Response:**
```json
{
  "id": 1,
  "result": {
    "userAgent": "codex/0.x.y"
  }
}
```

### 3. Send `initialized` Notification

After receiving the `initialize` response, the client **should** send the `initialized` notification (no params):

```json
{
  "method": "initialized"
}
```

### 4. Normal Operation

The client can now send any supported requests. The server sends notifications and server-initiated requests at any time.

### 5. Disconnect

Close the WebSocket connection (or close stdin for stdio). The server detects the disconnect and cleans up the connection state.

---

## Client → Server Requests

All requests follow the format:
```json
{ "method": "<method-name>", "id": <id>, "params": { ... } }
```

`params` is omitted (or set to `null`) for methods that take no parameters.

---

### Connection & Session Management

#### `initialize`
Negotiate capabilities. Must be the first message sent.

**Params:**
```typescript
{
  clientInfo: {
    name: string;        // e.g. "codex_vscode"
    title?: string;      // Human-readable display name
    version: string;     // Semver string
  };
  capabilities?: {
    experimentalApi?: boolean;                    // Opt into experimental methods
    optOutNotificationMethods?: string[];         // Suppress specific notifications
  };
}
```

**Response:** `{ userAgent: string }`

---

### Thread Lifecycle (v2 / current)

#### `thread/start`
Create a new conversation thread.

**Params:**
```typescript
{
  model?: string;
  modelProvider?: string;
  profile?: string;
  cwd?: string;                      // Working directory for the agent
  approvalPolicy?: AskForApproval;
  sandboxMode?: SandboxMode;
  instructions?: string;
  developerInstructions?: string;
  compactPrompt?: string;
  modelReasoningEffort?: ReasoningEffort;
  modelReasoningSummary?: ReasoningSummary;
  modelVerbosity?: Verbosity;
  analytics?: AnalyticsConfig;
  // Experimental fields omitted
}
```

**Response:**
```typescript
{
  threadId: string;           // UUID of the new thread
  model: string;
  reasoningEffort?: string;
  rolloutPath: string;        // Filesystem path to the thread's rollout file
}
```

After `thread/start`, the server emits a `thread/started` notification followed by a `thread/status/changed` notification.

---

#### `thread/resume`
Resume an existing thread (re-subscribe to its events).

**Params:**
```typescript
{
  threadId?: string;
  path?: string;              // Path to rollout file (alternative to threadId)
  overrides?: ThreadStartParams;   // Optional overrides for this session
}
```

**Response:**
```typescript
{
  threadId: string;
  model: string;
  initialMessages?: EventMsg[];    // Replayed history events
  rolloutPath: string;
}
```

---

#### `thread/fork`
Fork an existing thread into a new independent thread.

**Params:**
```typescript
{
  threadId?: string;
  path?: string;
  overrides?: ThreadStartParams;
}
```

**Response:** Same structure as `thread/resume` response.

---

#### `thread/archive`
Archive a thread (soft-delete, excluded from default list).

**Params:** `{ threadId: string }`
**Response:** `{}`

---

#### `thread/unarchive`
Restore an archived thread.

**Params:** `{ threadId: string }`
**Response:** `{}`

---

#### `thread/unsubscribe`
Stop receiving notifications for a thread on this connection (without archiving).

**Params:** `{ threadId: string }`
**Response:** `{}`

---

#### `thread/name/set`
Manually set a thread's display name.

**Params:** `{ threadId: string; name: string }`
**Response:** `{}`

---

#### `thread/rollback`
Roll back the last turn in a thread.

**Params:** `{ threadId: string }`
**Response:** `{}`

---

#### `thread/compact/start`
Trigger context compaction for a thread.

**Params:** `{ threadId: string }`
**Response:** `{}`

---

#### `thread/list`
List all threads with optional pagination.

**Params:**
```typescript
{
  pageSize?: number;
  cursor?: string;              // Pagination cursor
  modelProviders?: string[];    // Filter by model providers
}
```

**Response:**
```typescript
{
  items: ConversationSummary[];
  nextCursor?: string;
}
```

`ConversationSummary`:
```typescript
{
  conversationId: string;
  path: string;
  preview: string;
  timestamp?: string;
  updatedAt?: string;
  modelProvider: string;
  cwd: string;
  cliVersion: string;
  source: SessionSource;
  gitInfo?: {
    sha?: string;
    branch?: string;
    originUrl?: string;
  };
}
```

---

#### `thread/loaded/list`
List threads that are currently loaded in-memory.

**Params:** `{}`
**Response:** `{ items: ConversationSummary[] }`

---

#### `thread/read`
Read the full history of a thread.

**Params:** `{ threadId: string }`
**Response:** `{ items: TurnItem[] }`

---

### Turn Control

#### `turn/start`
Send a user message to start a new turn (the agent begins processing).

**Params:**
```typescript
{
  threadId: string;
  items: InputItem[];                // User message content
  approvalPolicy: AskForApproval;
  sandboxPolicy: SandboxPolicy;
  model: string;
  effort?: ReasoningEffort;
  summary: ReasoningSummary;
  outputSchema?: object;             // JSON Schema to constrain final response
  personality?: string;              // Personality preset name
  // Experimental fields
}
```

`InputItem` is a tagged union. The official API uses a flat format:
```typescript
| { type: "text";       text: string }
| { type: "image";      url: string }
| { type: "localImage"; path: string }
| { type: "skill";      name: string; path: string }   // invoke a named skill
| { type: "mention";    name: string; path: string }   // reference an app (path: "app://<slug>")
```

> **Note:** The v1 Rust source serialises `text`/`image`/`localImage` with a `data` wrapper (`{ type: "text", data: { text: "..." } }`). Use the flat format above for v2 `turn/start`; the `data`-wrapped form is a v1/internal detail.

**Response:** `{}`

The server emits `turn/started` immediately, then streams `item/*` notifications, and finally `turn/completed`.

---

#### `turn/steer`
Send a follow-up input to an in-progress turn (steer the agent mid-turn).

**Params:**
```typescript
{
  threadId: string;
  items: InputItem[];
}
```

**Response:** `{}`

---

#### `turn/interrupt`
Interrupt (cancel) an in-progress turn.

**Params:** `{ threadId: string }`

**Response:**
```typescript
{
  abortReason: TurnAbortReason;
}
```

`TurnAbortReason` values: `"userRequested"`, `"contextWindowExceeded"`, `"error"`, etc.

---

### Models & Features

#### `model/list`
List available models.

**Params:**
```typescript
{
  includeHidden?: boolean;
}
```

**Response:**
```typescript
{
  models: Model[];
}
```

---

#### `experimentalFeature/list`
List available experimental feature flags.

**Params:** `{}`
**Response:** `{ features: ExperimentalFeature[] }`

---

#### `collaborationMode/list` *(experimental)*
List collaboration mode presets.

**Params:** `{}`
**Response:** `{ modes: CollaborationMode[] }`

---

### Account & Auth

#### `account/login/start`
Begin an account login flow (API key or OAuth).

**Params:**
```typescript
{
  authMode: "apiKey" | "chatgpt" | "chatgptAuthTokens";
  apiKey?: string;   // Only for authMode = "apiKey"
}
```

**Response:**
```typescript
// For "chatgpt" auth:
{
  loginId: string;   // UUID
  authUrl: string;   // URL to open in browser for OAuth
}
// For "apiKey" auth:
{}
```

---

#### `account/login/cancel`
Cancel an in-progress OAuth login flow.

**Params:** `{ loginId: string }`
**Response:** `{}`

---

#### `account/logout`
Log out of the current account.

**Params:** none
**Response:** `{}`

---

#### `account/read`
Get current account details.

**Params:** `{ includeToken?: boolean; refreshToken?: boolean }`

**Response:**
```typescript
{
  authMethod?: "apiKey" | "chatgpt" | "chatgptAuthTokens";
  authToken?: string;
  requiresOpenaiAuth?: boolean;
  // additional account fields
}
```

---

#### `account/rateLimits/read`
Get current rate limit status.

**Params:** none
**Response:** `{ rateLimits: RateLimitSnapshot }`

---

#### `feedback/upload`
Upload feedback/telemetry.

**Params:** `{ ... feedback data ... }`
**Response:** `{}`

---

### Configuration API

#### `config/read`
Read the effective Codex configuration.

**Params:**
```typescript
{
  includeLayers?: boolean;   // Include per-layer breakdown
  cwd?: string;              // Resolve project layers from this directory
}
```

**Response:**
```typescript
{
  config: Config;
  origins: Record<string, ConfigLayerMetadata>;
  layers?: ConfigLayer[];    // Only if includeLayers = true
}
```

`Config` fields include: `model`, `reviewModel`, `modelProvider`, `approvalPolicy`, `sandboxMode`, `sandboxWorkspaceWrite`, `tools`, `profile`, `profiles`, `webSearch`, `analytics`, `apps`, etc.

Config layers (in ascending precedence):
1. `Mdm` — macOS MDM managed preferences (precedence 0)
2. `System` — `managed_config.toml` file (precedence 10)
3. `User` — `$CODEX_HOME/config.toml` (precedence 20)
4. `Project` — `.codex/` folder in project (precedence 25)
5. `SessionFlags` — CLI `-c`/`--config` overrides (precedence 30)
6. `LegacyManagedConfigTomlFromFile` (precedence 40)
7. `LegacyManagedConfigTomlFromMdm` (precedence 50)

---

#### `config/value/write`
Write a single configuration value.

**Params:**
```typescript
{
  keyPath: string;             // Dot-separated path, e.g. "model"
  value: any;
  mergeStrategy: "replace" | "upsert";
  filePath?: string;           // Defaults to user's config.toml
  expectedVersion?: string;    // Optimistic concurrency check
}
```

**Response:**
```typescript
{
  status: "ok" | "okOverridden";
  version: string;
  filePath: string;
  overriddenMetadata?: {
    message: string;
    overridingLayer: ConfigLayerMetadata;
    effectiveValue: any;
  };
}
```

Config write error codes (in `error.data`): `configLayerReadonly`, `configVersionConflict`, `configValidationError`, `configPathNotFound`, `configSchemaUnknownKey`, `userLayerNotFound`.

---

#### `config/batchWrite`
Write multiple configuration values atomically.

**Params:**
```typescript
{
  edits: Array<{ keyPath: string; value: any; mergeStrategy: "replace" | "upsert" }>;
  filePath?: string;
  expectedVersion?: string;
}
```

**Response:** Same as `config/value/write`.

---

#### `configRequirements/read`
Read managed/MDM configuration requirements (what values are locked down).

**Params:** none

**Response:**
```typescript
{
  requirements?: {
    allowedApprovalPolicies?: AskForApproval[];
    allowedSandboxModes?: SandboxMode[];
    allowedWebSearchModes?: string[];
    enforceResidency?: "us";
    network?: NetworkRequirements;  // experimental
  };
}
```

---

#### `config/mcpServer/reload`
Hot-reload MCP server configuration.

**Params:** none
**Response:** `{}`

---

#### `externalAgentConfig/detect`
Detect external agent config files (Claude, Cursor, etc.) that can be imported.

**Params:**
```typescript
{
  includeHome?: boolean;
  cwds?: string[];
}
```

**Response:** `{ items: ExternalAgentConfigMigrationItem[] }`

---

#### `externalAgentConfig/import`
Import detected external agent configurations.

**Params:** `{ migrationItems: ExternalAgentConfigMigrationItem[] }`
**Response:** `{}`

---

### MCP Servers

#### `mcpServer/oauth/login`
Start an OAuth login flow for a specific MCP server.

**Params:** `{ serverName: string; ... }`
**Response:** `{ authUrl: string; ... }`

---

#### `mcpServerStatus/list`
List status of all configured MCP servers.

**Params:** `{}`
**Response:** `{ servers: McpServerStatus[] }`

---

### Skills & Apps

#### `skills/list`
List available Codex skills.

**Params:** `{}`
**Response:** `{ skills: SkillMetadata[] }`

---

#### `skills/remote/list`
List remotely available skills.

**Params:** `{}`
**Response:** `{ skills: SkillMetadata[] }`

---

#### `skills/remote/export`
Export skills to remote storage.

**Params:** `{ ... }`
**Response:** `{}`

---

#### `skills/config/write`
Update skills configuration.

**Params:** `{ ... }`
**Response:** `{}`

---

#### `app/list`
List available Codex app integrations.

**Params:** `{}`
**Response:** `{ apps: AppInfo[] }`

---

### File Search

#### `fuzzyFileSearch`
Perform a one-shot fuzzy file search.

**Params:**
```typescript
{
  query: string;
  roots: string[];
  cancellationToken?: string;   // Cancels any previous search with same token
}
```

**Response:**
```typescript
{
  files: Array<{
    root: string;
    path: string;
    fileName: string;
    score: number;
    indices?: number[];   // Matched character indices for highlighting
  }>;
}
```

---

#### `fuzzyFileSearch/sessionStart` *(experimental)*
Start a persistent search session.

**Params:** `{ sessionId: string; roots: string[] }`
**Response:** `{}`

---

#### `fuzzyFileSearch/sessionUpdate` *(experimental)*
Update query for an active search session.

**Params:** `{ sessionId: string; query: string }`
**Response:** `{}`

The server emits `fuzzyFileSearch/sessionUpdated` notifications with incremental results.

---

#### `fuzzyFileSearch/sessionStop` *(experimental)*
Stop a persistent search session.

**Params:** `{ sessionId: string }`
**Response:** `{}`

---

### Utilities

#### `command/exec`
Execute a shell command under the server's sandbox.

**Params:**
```typescript
{
  command: string[];
  timeoutMs?: number;
  cwd?: string;
  sandboxPolicy?: SandboxPolicy;
}
```

**Response:**
```typescript
{
  exitCode: number;
  stdout: string;
  stderr: string;
}
```

---

#### `review/start`
Start a code review turn.

**Params:** `{ threadId: string; ... }`
**Response:** `{}`

---

#### `windowsSandbox/setupStart`
Trigger async Windows sandbox setup.

**Params:**
```typescript
{
  mode: "elevated" | "unelevated";  // "elevated" = elevated sandbox; "unelevated" = legacy preflight path
}
```
**Response:** `{}`

The server emits `windowsSandbox/setupCompleted` when setup finishes.

---

#### `mock/experimentalMethod` *(experimental, test-only)*
Used to validate experimental API gating. Not for production use.

---

### Realtime (Experimental)

These methods require `experimentalApi: true` in capabilities.

#### `thread/realtime/start`
Start a realtime (audio/voice) session on a thread.

**Params:** `{ threadId: string; ... }`
**Response:** `{}`

---

#### `thread/realtime/appendAudio`
Append an audio frame to an active realtime session.

**Params:** `{ threadId: string; audioData: string; ... }`
**Response:** `{}`

---

#### `thread/realtime/appendText`
Append text input to an active realtime session.

**Params:** `{ threadId: string; text: string }`
**Response:** `{}`

---

#### `thread/realtime/stop`
Stop the active realtime session.

**Params:** `{ threadId: string }`
**Response:** `{}`

---

### Deprecated v1 Methods

These methods are still supported but should not be used in new clients. Use the v2 equivalents.

| Deprecated Method | v2 Replacement |
|-------------------|----------------|
| `newConversation` | `thread/start` |
| `resumeConversation` | `thread/resume` |
| `forkConversation` | `thread/fork` |
| `archiveConversation` | `thread/archive` |
| `listConversations` | `thread/list` |
| `getConversationSummary` | `thread/read` |
| `sendUserMessage` | `turn/start` |
| `sendUserTurn` | `turn/start` |
| `interruptConversation` | `turn/interrupt` |
| `addConversationListener` | Implicit on `thread/resume` |
| `removeConversationListener` | `thread/unsubscribe` |
| `loginApiKey` | `account/login/start` |
| `loginChatGpt` | `account/login/start` |
| `cancelLoginChatGpt` | `account/login/cancel` |
| `logoutChatGpt` | `account/logout` |
| `getAuthStatus` | `account/read` |
| `getUserSavedConfig` | `config/read` |
| `setDefaultModel` | `config/value/write` |
| `getUserAgent` | (read from `initialize` response) |
| `userInfo` | `account/read` |
| `execOneOffCommand` | `command/exec` |
| `gitDiffToRemote` | (no direct replacement) |

---

## Server → Client Requests (Approval Callbacks)

The server can send requests to the client that **require a response**. These have the same JSON-RPC request structure (with an `id`) and the client must respond.

These are sent when the agent needs human-in-the-loop approval.

---

### `item/commandExecution/requestApproval` (v2)
Request approval to execute a shell command.

**Server sends:**
```json
{
  "method": "item/commandExecution/requestApproval",
  "id": "srv-1",
  "params": {
    "threadId": "...",
    "callId": "...",
    "command": ["ls", "-la"],
    "cwd": "/path/to/dir",
    "reason": "Optional explanation",
    "parsedCmd": [ ... ]
  }
}
```

**Client responds:**
```json
{
  "id": "srv-1",
  "result": {
    "decision": "accept"
  }
}
```

`CommandExecutionApprovalDecision` values:
- `"accept"` — approve and run
- `"acceptForSession"` — approve and cache for the session
- `"acceptWithExecpolicyAmendment"` — approve and update exec policy rules
- `"applyNetworkPolicyAmendment"` — apply a network policy rule
- `"decline"` — deny; agent continues turn
- `"cancel"` — deny and interrupt the turn

---

### `item/fileChange/requestApproval` (v2)
Request approval for a file write/patch.

**Server sends params:**
```typescript
{
  threadId: string;
  callId: string;
  fileChanges: Record<string, FileChange>;
  reason?: string;
  grantRoot?: string;
}
```

**Client responds with:**
```typescript
{
  decision: "accept" | "acceptForSession" | "decline" | "cancel";
}
```

- `"accept"` — approve the changes
- `"acceptForSession"` — approve and cache decision for the session
- `"decline"` — deny; agent continues turn
- `"cancel"` — deny and interrupt the turn

---

### `item/tool/requestUserInput` (v2)
Ask the user a question from within a tool call.

**Server sends params:**
```typescript
{
  threadId: string;
  callId: string;
  prompt: string;
  choices?: string[];
}
```

**Client responds with:** `{ input: string }`

---

### `item/tool/call` (v2 — Dynamic Tools)
Execute a dynamic tool registered by the client (client-side tool call).

**Server sends params:**
```typescript
{
  threadId: string;
  callId: string;
  name: string;
  input: object;   // JSON matching the tool's input schema
}
```

**Client responds with:** `{ output: string }` (string-serialized tool result)

---

### `account/chatgptAuthTokens/refresh` (v2)
Ask the client to supply fresh ChatGPT auth tokens (for `chatgptAuthTokens` mode).

**Server sends params:** `{ ... }`
**Client responds with:** `{ accessToken: string; expiresAt: string; ... }`

The server waits up to 10 seconds (`EXTERNAL_AUTH_REFRESH_TIMEOUT`) for this response.

---

### Deprecated v1 Approval Methods

| Method | Replacement |
|--------|-------------|
| `applyPatchApproval` | `item/fileChange/requestApproval` |
| `execCommandApproval` | `item/commandExecution/requestApproval` |

---

## Server → Client Notifications

Notifications are fire-and-forget — no response is expected.

All notifications follow the format:
```json
{ "method": "<notification-name>", "params": { ... } }
```

Specific notifications can be suppressed per-connection via `optOutNotificationMethods` in `initialize`.

---

### Error Notification

#### `error`
Emitted when a turn fails with a fatal error (in addition to `turn/completed` with `status: "failed"`).
```typescript
{
  threadId: string;
  message: string;
  codexErrorInfo?: string;     // One of the CodexErrorInfo variant names
  additionalDetails?: string;
  httpStatusCode?: number;     // Present when error originated from an HTTP response
}
```

---

### Thread Lifecycle Notifications

#### `thread/started`
Emitted after `thread/start` or `thread/resume` completes.
```typescript
{
  threadId: string;
  model: string;
  reasoningEffort?: string;
  rolloutPath: string;
}
```

#### `thread/status/changed`
Emitted when the thread's status changes.
```typescript
{
  threadId: string;
  status: ThreadStatus;
}
```

`ThreadStatus` values: `"notLoaded"`, `"idle"`, `"active"`, `"systemError"`.
When `active`, also includes `activeFlags: ThreadActiveFlag[]` where flags are `"waitingOnApproval"` or `"waitingOnUserInput"`.

#### `thread/closed`
The thread was closed or unloaded.
```typescript
{ threadId: string }
```

#### `thread/archived`
Thread was archived.
```typescript
{ threadId: string }
```

#### `thread/unarchived`
Thread was restored from archive.
```typescript
{ threadId: string }
```

#### `thread/name/updated`
The thread's display name was updated.
```typescript
{ threadId: string; name: string }
```

#### `thread/tokenUsage/updated`
Running token usage update.
```typescript
{
  threadId: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}
```

#### `thread/compacted` *(deprecated)*
Context was compacted. Use `ContextCompaction` item type instead.

---

### Turn Lifecycle Notifications

#### `turn/started`
A new turn has begun.
```typescript
{
  threadId: string;
  turnId: string;
}
```

#### `turn/completed`
A turn finished (success, interruption, or failure).
```typescript
{
  threadId: string;
  turnId: string;
  status: "completed" | "interrupted" | "failed";
  abortReason?: TurnAbortReason;
  codexErrorInfo?: CodexErrorInfo;
}
```

`CodexErrorInfo` variants:
- `"contextWindowExceeded"`
- `"usageLimitExceeded"`
- `"serverOverloaded"`
- `"httpConnectionFailed"` + `httpStatusCode?: number`
- `"responseStreamConnectionFailed"` + `httpStatusCode?: number`
- `"internalServerError"`
- `"unauthorized"`
- `"badRequest"`
- `"threadRollbackFailed"`
- `"sandboxError"`
- `"responseStreamDisconnected"` + `httpStatusCode?: number`
- `"responseTooManyFailedAttempts"` + `httpStatusCode?: number`
- `"other"`

#### `turn/diff/updated`
A code diff has been updated during the turn.
```typescript
{
  threadId: string;
  diff: string;
}
```

#### `turn/plan/updated`
The agent's execution plan has been updated.
```typescript
{
  threadId: string;
  plan: PlanItem[];
}
```

---

### Item (Streaming) Notifications

Items represent individual steps within a turn (messages, tool calls, file changes, etc.).

**`itemType` values (`TurnItem` discriminant):**

| Type | Description |
|------|-------------|
| `userMessage` | User input with content array |
| `agentMessage` | Accumulated agent reply; includes optional `phase` |
| `plan` | Proposed execution plan text |
| `reasoning` | Model reasoning with `summary` and `content` |
| `commandExecution` | Shell command with `command`, `cwd`, `status`, and output |
| `fileChange` | Proposed file edits with diff and `status` |
| `mcpToolCall` | MCP tool invocation with `server`, `tool`, and `status` |
| `collabToolCall` | Collaboration tool invocation |
| `webSearch` | Web search request with `query` and optional `action` |
| `imageView` | Image viewer invocation with `path` |
| `contextCompaction` | History compaction event |
| `enteredReviewMode` | Reviewer started; includes `review` object |
| `exitedReviewMode` | Reviewer finished; includes `review` object |

All item types emit `item/started` at creation and `item/completed` when finalised.

#### `item/started`
An item has started.
```typescript
{
  threadId: string;
  itemId: string;
  itemType: string;
}
```

#### `item/completed`
Final, authoritative item state.
```typescript
{
  threadId: string;
  itemId: string;
  item: TurnItem;
}
```

#### `item/agentMessage/delta`
Streaming delta for the agent's text response.
```typescript
{
  threadId: string;
  itemId: string;
  delta: string;      // Text chunk
}
```

#### `item/plan/delta`
Streaming delta for plan items *(experimental)*.

#### `item/commandExecution/outputDelta`
Streaming stdout/stderr from a shell command being executed.
```typescript
{
  threadId: string;
  itemId: string;
  callId: string;
  stream: "stdout" | "stderr";
  data: string;
}
```

#### `item/commandExecution/terminalInteraction`
Terminal interaction event during command execution.
```typescript
{
  threadId: string;
  itemId: string;
  callId: string;
  data: string;
}
```

#### `item/fileChange/outputDelta`
Streaming delta of a file being written.
```typescript
{
  threadId: string;
  itemId: string;
  callId: string;
  delta: string;
}
```

#### `item/mcpToolCall/progress`
Progress update from an MCP tool call.
```typescript
{
  threadId: string;
  itemId: string;
  callId: string;
  progress: string;
}
```

#### `item/reasoning/summaryTextDelta`
Streaming delta for reasoning summary text.

#### `item/reasoning/summaryPartAdded`
A reasoning summary part was added.

#### `item/reasoning/textDelta`
Streaming delta for raw reasoning text.

#### `rawResponseItem/completed`
Internal event for Codex Cloud use. Raw response item completed.

---

### Server Request State

#### `serverRequest/resolved`
A pending server-initiated request (approval callback) was resolved.
```typescript
{
  requestId: string;
  resolution: "approved" | "denied" | "cancelled";
}
```

---

### Account Notifications

#### `account/updated`
Account state changed (e.g., auth, plan, credits).
```typescript
{
  authMethod?: "apiKey" | "chatgpt" | "chatgptAuthTokens";
  planType?: string;
  creditsSnapshot?: CreditsSnapshot;
  rateLimits?: RateLimitSnapshot;
}
```

#### `account/login/completed`
An OAuth login flow completed.
```typescript
{
  loginId: string;
  success: boolean;
  error?: string;
}
```

#### `account/rateLimits/updated`
Rate limit state changed.
```typescript
{
  rateLimits: RateLimitSnapshot;
}
```

---

### App & Config Notifications

#### `app/list/updated`
The list of available Codex app integrations changed.

#### `model/rerouted`
The model was automatically rerouted.
```typescript
{
  threadId: string;
  fromModel: string;
  toModel: string;
  reason: "highRiskCyberActivity";
}
```

#### `deprecationNotice`
The client is using a deprecated method or feature.
```typescript
{
  message: string;
  method?: string;
}
```

#### `configWarning`
A configuration warning (e.g., unknown key, deprecated setting).
```typescript
{
  message: string;
  key?: string;
}
```

---

### MCP Notifications

#### `mcpServer/oauthLogin/completed`
An MCP server OAuth login completed.

---

### File Search Notifications

#### `fuzzyFileSearch/sessionUpdated` *(experimental)*
Incremental results from an active search session.
```typescript
{
  sessionId: string;
  query: string;
  files: FuzzyFileSearchResult[];
}
```

#### `fuzzyFileSearch/sessionCompleted` *(experimental)*
A search session has finished processing.
```typescript
{ sessionId: string }
```

---

### Realtime Notifications *(experimental)*

#### `thread/realtime/started`
Realtime session started.

#### `thread/realtime/itemAdded`
A new item was added to the realtime session.

#### `thread/realtime/outputAudio/delta`
Streaming audio output delta.

#### `thread/realtime/error`
An error occurred in the realtime session.

#### `thread/realtime/closed`
The realtime session was closed.

---

### Windows-specific Notifications

#### `windows/worldWritableWarning`
Warning about world-writable directories that the sandbox cannot protect.

#### `windowsSandbox/setupCompleted`
Windows sandbox setup finished.

---

### Deprecated Notifications

| Deprecated Notification | Replacement |
|------------------------|-------------|
| `authStatusChange` | `account/updated` |
| `loginChatGptComplete` | `account/login/completed` |
| `sessionConfigured` | `thread/started` + `thread/status/changed` |

---

## Client → Server Notifications

Currently only one client notification is defined:

#### `initialized`
Sent by the client after it has processed the `initialize` response.
```json
{ "method": "initialized" }
```

No params. No response expected.

---

## Core Data Types

### `AskForApproval` (Approval Policy)

Wire values (kebab-case):
```typescript
"untrusted"    // Prompt for untrusted commands
"on-failure"   // Only prompt if command fails
"on-request"   // Agent requests approval explicitly
{              // Fully customized reject config
  "reject": true,
  sandboxApproval: boolean,
  rules: boolean,
  mcpElicitations: boolean
}
"never"        // Never prompt (auto-approve all)
```

### `SandboxMode`

Wire values (kebab-case):
```typescript
"read-only"           // Agent can only read files
"workspace-write"     // Agent can write within the workspace
"danger-full-access"  // Unrestricted filesystem access
```

### `ReasoningEffort`

Values: `"low"`, `"medium"`, `"high"`

### `ReasoningSummary`

Values: `"auto"`, `"concise"`, `"detailed"`, `"none"`

### `AuthMode`

Wire values (lowercase):
```typescript
"apikey"            // OpenAI API key
"chatgpt"           // ChatGPT OAuth managed by Codex
"chatgptAuthTokens" // External token supply (internal use)
```

### `SessionSource`

Values indicating how the thread was created:
`"cli"`, `"vsCode"`, `"exec"`, `"appServer"`, `"subAgent"`, `"unknown"`

### `ReviewDecision` (v1 / legacy)

```typescript
"approved"
"approved_for_session"
"abort"
"denied"
```

### `InputItem`

Official (v2) flat format:
```typescript
{ "type": "text";       "text": string }
{ "type": "image";      "url": string }
{ "type": "localImage"; "path": string }
{ "type": "skill";      "name": string; "path": string }   // full path to SKILL.md
{ "type": "mention";    "name": string; "path": string }   // path: "app://<slug>"
```

> **Format note:** The v1 Rust source wraps `text`/`image`/`localImage` in a `data` field (`{ "type": "text", "data": { "text": "..." } }`). This is a v1/internal serialisation detail — use the flat format above for v2 `turn/start`.

`TextElement` (v1, used within `text` items when annotating spans):
```typescript
{
  byteRange: { start: number; end: number };  // Byte offsets in parent text
  placeholder?: string;
}
```

#### Skills invocation
Trigger a skill by prefixing its name with `$` in a text message (e.g. `$skill-creator`), or supply an explicit `skill` input item with the full `path` to `SKILL.md`. The skill response includes an `interface` and `dependencies` object describing required env vars and MCP tool dependencies.

#### App (Connector) mentions
Trigger an app connector with `$<app-slug>` in text, or supply a `mention` input item with `path: "app://<slug>"`. Available apps and their metadata (`id`, `name`, `description`, `logoUrl`, `logoUrlDark`, `isAccessible`, `isEnabled`) are returned by `app/list`.

### `ThreadId`

A UUID string, e.g. `"67e55044-10b1-426f-9247-bb680e5fe0c8"`.

---

## Error Codes

Standard JSON-RPC error codes used in error responses:

| Code | Constant | Meaning |
|------|----------|---------|
| `-32600` | `INVALID_REQUEST_ERROR_CODE` | Invalid JSON-RPC request structure |
| `-32602` | `INVALID_PARAMS_ERROR_CODE` | Invalid method parameters |
| `-32603` | `INTERNAL_ERROR_CODE` | Internal server error |
| `-32001` | `OVERLOADED_ERROR_CODE` | Server overloaded; retry later (WebSocket only) |
| `"input_too_large"` | `INPUT_TOO_LARGE_ERROR_CODE` | Input exceeded size limit (string code in `data`) |

When the channel is full on WebSocket, the server responds immediately with error code `-32001` instead of blocking.

---

## Thread Status & Active Flags

```typescript
type ThreadStatus =
  | "notLoaded"          // Thread not in memory
  | "idle"               // Loaded, no active turn
  | { active: { activeFlags: ThreadActiveFlag[] } }
  | "systemError";       // Fatal error, requires user action

type ThreadActiveFlag =
  | "waitingOnApproval"     // Paused awaiting an approval callback
  | "waitingOnUserInput";   // Paused awaiting user input
```

---

## Approval & Sandbox Policies

### `SandboxPolicy` (runtime, per-turn)

Configures what the sandbox allows for a specific turn. Distinct from `SandboxMode` which is a global config. Four policy types are supported:

#### `dangerFullAccess`
No restrictions.
```typescript
{ type: "dangerFullAccess" }
```

#### `readOnly`
Read-only filesystem access with optional restricted roots.
```typescript
{
  type: "readOnly";
  access?: {
    type: "restricted";
    includePlatformDefaults?: boolean;  // Append curated macOS platform defaults
    readableRoots?: string[];
  };
  networkAccess?: boolean;
}
```

#### `workspaceWrite`
Write access within the workspace, with optional read-only path restrictions.
```typescript
{
  type: "workspaceWrite";
  writableRoots?: string[];
  readOnlyAccess?: {
    type: "restricted";
    includePlatformDefaults?: boolean;
    readableRoots?: string[];
  };
  networkAccess?: boolean;
  excludeTmpdirEnvVar?: boolean;
  excludeSlashTmp?: boolean;
}
```

#### `externalSandbox`
The caller is responsible for sandboxing; the server applies no restrictions.
```typescript
{
  type: "externalSandbox";
  networkAccess?: "restricted" | "enabled";  // "restricted" is default
}
```

### `ExecPolicyAmendment`

Proposed change to the exec policy rules when the user selects `acceptWithExecpolicyAmendment`:
```typescript
{
  // policy rule details
}
```

### `NetworkPolicyAmendment`

Proposed network policy rule change:
```typescript
{
  host: string;
  protocol: "http" | "https" | "socks5Tcp" | "socks5Udp";
  action: "allow" | "deny";
}
```

---

## Experimental API Flag

Methods and notifications marked **experimental** are only available if the client sends `"experimentalApi": true` in `initialize`:

```json
{
  "method": "initialize",
  "id": 1,
  "params": {
    "clientInfo": { ... },
    "capabilities": {
      "experimentalApi": true
    }
  }
}
```

If a client without `experimentalApi: true` sends an experimental method, the server returns an error.

Experimental methods as of current source:
- `thread/backgroundTerminals/clean`
- `thread/realtime/start`
- `thread/realtime/appendAudio`
- `thread/realtime/appendText`
- `thread/realtime/stop`
- `collaborationMode/list`
- `fuzzyFileSearch/sessionStart`
- `fuzzyFileSearch/sessionUpdate`
- `fuzzyFileSearch/sessionStop`
- `mock/experimentalMethod` (test-only)

Experimental notifications (only sent if `experimentalApi: true`):
- `thread/realtime/started`
- `thread/realtime/itemAdded`
- `thread/realtime/outputAudio/delta`
- `thread/realtime/error`
- `thread/realtime/closed`

---

## Environment Variables & Logging

| Variable | Effect |
|----------|--------|
| `CODEX_APP_SERVER_MANAGED_CONFIG_PATH` | Override managed config file path |
| `LOG_FORMAT` | Set to `"json"` for structured JSON logging to stderr |
| `RUST_LOG` | Standard Rust logging level filter (e.g. `RUST_LOG=debug`) |

---

## Quick-Start Examples

### Build and Start (WebSocket)

```bash
# From codex-rs/
cargo build -p codex-cli --bin codex

# Start app server on WebSocket
./target/debug/codex app-server --listen ws://127.0.0.1:4222
```

### Connect and Initialize (JavaScript/Node)

```javascript
const WebSocket = require("ws");

const ws = new WebSocket("ws://127.0.0.1:4222");
let msgId = 1;

ws.on("open", () => {
  // 1. Initialize
  ws.send(JSON.stringify({
    method: "initialize",
    id: msgId++,
    params: {
      clientInfo: { name: "my-app", version: "1.0.0" },
      capabilities: { experimentalApi: false }
    }
  }));
});

ws.on("message", (raw) => {
  const msg = JSON.parse(raw);

  // Handle initialize response
  if (msg.id === 1 && msg.result?.userAgent) {
    // 2. Send initialized notification
    ws.send(JSON.stringify({ method: "initialized" }));

    // 3. Start a thread
    ws.send(JSON.stringify({
      method: "thread/start",
      id: msgId++,
      params: {
        model: "codex-mini-latest",
        cwd: "/home/user/myproject",
        approvalPolicy: "never",
        sandboxMode: "workspace-write"
      }
    }));
  }

  // Listen for thread started
  if (msg.method === "thread/started") {
    const threadId = msg.params.threadId;

    // 4. Send a user message
    ws.send(JSON.stringify({
      method: "turn/start",
      id: msgId++,
      params: {
        threadId,
        items: [{ type: "text", data: { text: "List files in this directory" } }],
        model: "codex-mini-latest",
        approvalPolicy: "never",
        sandboxPolicy: {},
        summary: "auto"
      }
    }));
  }

  // Stream agent responses
  if (msg.method === "item/agentMessage/delta") {
    process.stdout.write(msg.params.delta);
  }

  if (msg.method === "turn/completed") {
    console.log("\n--- Turn complete ---");
    ws.close();
  }
});
```

### Send a Message and Wait for Response

```bash
# Using the test client:
cargo run -p codex-app-server-test-client -- \
  --codex-bin ./target/debug/codex \
  send-message-v2 "What files are in this directory?"
```

### List Threads

```bash
cargo run -p codex-app-server-test-client -- thread-list --limit 10
```

### Watch Raw Traffic

```bash
cargo run -p codex-app-server-test-client -- watch
```

### Example: Full Turn with Approval Handling

```javascript
// Handle server-initiated approval request
ws.on("message", (raw) => {
  const msg = JSON.parse(raw);

  if (msg.method === "item/commandExecution/requestApproval") {
    const { id, params } = msg;
    console.log("Approval needed for:", params.command.join(" "));

    // Respond with decision
    ws.send(JSON.stringify({
      id,
      result: { decision: "accept" }
    }));
  }
});
```

---

## Architecture Notes

- The server runs a **processor task** (handles incoming messages, routes to handlers) and an **outbound router task** (routes outgoing messages to the correct connection).
- Each connection is identified by a `ConnectionId` (monotonically increasing `u64`).
- Thread subscriptions are per-connection — a single thread can have multiple subscribers across multiple connections.
- The server supports **graceful restart** via a `DisconnectAll` signal that closes all connections without terminating the process.
- Server-initiated requests use negative integer IDs (starting from -1, decrementing) to avoid collision with client-generated IDs.
