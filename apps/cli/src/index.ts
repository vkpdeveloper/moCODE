import { program } from "commander";

import { activateRegistryAgent } from "./agent-registry";
import { listAgentInventory } from "./agent-inventory";
import { uninstallManagedAgent } from "./agents";
import {
  confirmUninstall,
  runTask,
  selectAgent,
  showInstalledAgents,
  showResult,
} from "./cli-ui";
import { StateDatabase } from "./db";
import { getLogger, isVerboseLoggingEnabled, serializeError } from "./logger";
import { getStatePaths } from "./paths";
import { startDaemon } from "./daemon";

const DEFAULT_PORT = "4058";
const CLI_VERSION = "0.1.0";
const logger = getLogger("cli");

type PortOptions = {
  port: string;
};

type ActivateOptions = {
  force?: boolean;
  dryRun?: boolean;
};

type UninstallOptions = Record<string, never>;

type TableRow = Record<string, string>;

function parsePort(value: string) {
  const port = Number(value);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error(`Invalid port: ${value}`);
  }
  return port;
}

function withDatabase<T>(handler: (db: StateDatabase) => Promise<T> | T) {
  const paths = getStatePaths();
  const db = new StateDatabase(paths.databasePath);

  return Promise.resolve()
    .then(() => handler(db))
    .finally(() => {
      db.close();
    });
}

function truncate(value: string, width: number) {
  if (value.length <= width) {
    return value;
  }
  return `${value.slice(0, Math.max(0, width - 1))}…`;
}

function printTable(rows: TableRow[], columns: Array<{ key: string; label: string }>) {
  if (rows.length === 0) {
    return;
  }

  const widths = columns.map(({ key, label }) => {
    const cellWidth = Math.max(...rows.map((row) => row[key]?.length ?? 0), label.length);
    return Math.min(cellWidth, 48);
  });

  const renderLine = (row: TableRow) =>
    columns
      .map(({ key }, index) => truncate(row[key] ?? "", widths[index]!).padEnd(widths[index]!))
      .join("  ");

  console.log(renderLine(Object.fromEntries(columns.map(({ key, label }) => [key, label]))));
  console.log(widths.map((width) => "-".repeat(width)).join("  "));

  for (const row of rows) {
    console.log(renderLine(row));
  }
}

async function runStartCommand(options: PortOptions) {
  const port = parsePort(options.port);
  logger.info("start command invoked", { port });
  const instance = await startDaemon({ port });
  console.log(`moCODE CLI listening on http://127.0.0.1:${port}`);

  const shutdown = () => {
    instance.stop();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

async function runStatusCommand(options: PortOptions) {
  const port = parsePort(options.port);
  logger.info("status command invoked", { port });
  const response = await fetch(`http://127.0.0.1:${port}/v1/health`).catch(() => null);

  if (!response?.ok) {
    console.log("daemon: offline");
    return;
  }

  const body = (await response.json()) as Record<string, unknown>;
  printTable(
    [
      {
        status: "online",
        port: String(body.port ?? port),
        device: String(body.deviceName ?? "-"),
        version: String(body.version ?? "-"),
      },
    ],
    [
      { key: "status", label: "STATUS" },
      { key: "port", label: "PORT" },
      { key: "device", label: "DEVICE" },
      { key: "version", label: "VERSION" },
    ],
  );
}

async function runPairCommand(options: PortOptions) {
  const port = parsePort(options.port);
  logger.info("pair command invoked", { port });
  const response = await fetch(`http://127.0.0.1:${port}/v1/pairing/code`, {
    method: "POST",
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Failed to create pairing code: ${body}`);
  }

  const body = (await response.json()) as { code: string; expiresInSeconds: number };
  printTable(
    [
      {
        code: body.code,
        expires: `${body.expiresInSeconds}s`,
      },
    ],
    [
      { key: "code", label: "PAIRING CODE" },
      { key: "expires", label: "EXPIRES IN" },
    ],
  );
}

async function runAgentListCommand() {
  await withDatabase(async (db) => {
    logger.info("agents list command invoked");
    const paths = getStatePaths();
    const inventory = await listAgentInventory(db, paths, logger);
    if (inventory.note) {
      console.log(inventory.note);
    }
    showInstalledAgents(inventory.installed);
  });
}

async function resolveAgentActivationTarget(
  db: StateDatabase,
  agentId: string | undefined,
) {
  const selectedAgentId = agentId?.trim();
  if (selectedAgentId) {
    return selectedAgentId;
  }

  const paths = getStatePaths();
  const inventory = await listAgentInventory(db, paths, logger);
  if (inventory.installable.length === 0) {
    throw new Error("No installable agents are available.");
  }

  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error("No agent ID provided. Pass one explicitly, for example `mocode agents install codex-acp`.");
  }

  return await selectAgent({
    message: "Select an agent to install",
    items: inventory.installable,
  });
}

async function resolveManagedAgentUninstallTarget(
  db: StateDatabase,
  agentId: string | undefined,
) {
  const selectedAgentId = agentId?.trim();
  if (selectedAgentId) {
    return selectedAgentId;
  }

  const paths = getStatePaths();
  const inventory = await listAgentInventory(db, paths, logger);
  if (inventory.uninstallable.length === 0) {
    throw new Error("No managed agents are available to uninstall.");
  }

  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error("No agent ID provided. Pass one explicitly, for example `mocode agents uninstall cursor`.");
  }

  return await selectAgent({
    message: "Select an agent to uninstall",
    items: inventory.uninstallable,
  });
}

async function runActivateCommand(agentId: string | undefined, options: ActivateOptions) {
  await withDatabase(async (db) => {
    const paths = getStatePaths();
    logger.info("activate command invoked", {
      agentId: agentId ?? null,
      force: Boolean(options.force),
      dryRun: Boolean(options.dryRun),
    });

    const selectedAgentId = await resolveAgentActivationTarget(db, agentId);
    if (!selectedAgentId) {
      console.log("Install cancelled.");
      return;
    }

    const inventory = await listAgentInventory(db, paths, logger);
    const selectedAgentName =
      inventory.installable.find((item) => item.id === selectedAgentId)?.name ??
      inventory.installed.find((item) => item.id === selectedAgentId)?.name ??
      selectedAgentId;

    const activate = () =>
      activateRegistryAgent(db, paths, selectedAgentId, {
        force: Boolean(options.force),
        dryRun: Boolean(options.dryRun),
        logger,
      });

    const useActivationTui = process.stdin.isTTY && process.stdout.isTTY && !options.dryRun;

    const result = useActivationTui
      ? await runTask({
          taskLabel: `Installing ${selectedAgentName}`,
          task: async (update) =>
            await activateRegistryAgent(db, paths, selectedAgentId, {
              force: Boolean(options.force),
              dryRun: false,
              logger,
              onProgress: (event) => {
                update(event);
              },
            }),
          isFailure: (taskResult) => taskResult.status === "failed",
          formatSuccess: (taskResult) => taskResult.message,
          formatError: (error) => (error instanceof Error ? error.message : String(error)),
        })
      : await activate();

    if (useActivationTui) {
      if (result.status === "failed") {
        process.exitCode = 1;
      }
      return;
    }

    printTable(
      [
        {
          id: result.agentId,
          status: result.status,
          binary: result.binaryPath ?? "-",
          message: result.message,
        },
      ],
      [
        { key: "id", label: "AGENT" },
        { key: "status", label: "STATUS" },
        { key: "binary", label: "BINARY" },
        { key: "message", label: "DETAIL" },
      ],
    );

    if (result.status === "failed") {
      process.exitCode = 1;
    }
  });
}

async function runUninstallAgentCommand(
  agentId: string | undefined,
  _options: UninstallOptions,
) {
  await withDatabase(async (db) => {
    const paths = getStatePaths();
    logger.info("agent uninstall command invoked", {
      agentId: agentId ?? null,
    });

    const selectedAgentId = await resolveManagedAgentUninstallTarget(db, agentId);
    if (!selectedAgentId) {
      console.log("Uninstall cancelled.");
      return;
    }

    const useUninstallTui = process.stdin.isTTY && process.stdout.isTTY;
    if (useUninstallTui) {
      const managedInventory = await listAgentInventory(db, paths, logger);
      const selectedItem =
        managedInventory.uninstallable.find((item) => item.id === selectedAgentId) ?? null;

      if (selectedItem) {
        const confirmed = await confirmUninstall(selectedItem.name);
        if (!confirmed) {
          console.log("Uninstall cancelled.");
          return;
        }
      }
    }

    const result = await uninstallManagedAgent(db, paths, selectedAgentId);

    if (useUninstallTui) {
      showResult(result.message, result.status === "uninstalled" ? "success" : "danger");
    } else {
      printTable(
        [
          {
            id: result.agentId,
            status: result.status,
            message: result.message,
          },
        ],
        [
          { key: "id", label: "AGENT" },
          { key: "status", label: "STATUS" },
          { key: "message", label: "DETAIL" },
        ],
      );
    }

    if (result.status !== "uninstalled") {
      process.exitCode = 1;
    }
  });
}

function addPortOption(command: ReturnType<typeof program.command>) {
  return command.option("--port <port>", "Port to use", DEFAULT_PORT);
}

program
  .name("mocode")
  .description("moCODE local daemon and ACP agent CLI")
  .version(CLI_VERSION)
  .option("-v, --verbose", "Enable CLI logging")
  .showHelpAfterError()
  .showSuggestionAfterError();

addPortOption(program.command("start").description("Start the local moCODE daemon")).action(runStartCommand);

addPortOption(program.command("status").description("Inspect daemon health")).action(runStatusCommand);

addPortOption(program.command("pair").description("Create a 6-digit pairing code")).action(runPairCommand);

const agents = program
  .command("agents")
  .alias("agent")
  .description("Manage local and ACP agents");
agents.command("list").description("List installed ACP agents").action(runAgentListCommand);
agents
  .command("install")
  .description("Install an ACP agent")
  .argument("[agentId]", "Agent ID, such as codex-acp or cursor")
  .option("--force", "Reinstall the managed wrapper even if the agent is already available")
  .option("--dry-run", "Print the planned activation step without installing anything")
  .action(runActivateCommand);
agents
  .command("uninstall")
  .description("Remove a managed ACP agent")
  .argument("[agentId]", "Managed agent ID to uninstall")
  .action(runUninstallAgentCommand);

const acp = program.command("acp").description("Compatibility commands for ACP agents");
acp.command("list").description("List installed ACP agents").action(runAgentListCommand);
acp
  .command("activate")
  .description("Install an ACP agent")
  .argument("[agentId]", "Registry agent ID, such as codex-acp or cursor")
  .option("--force", "Reinstall the managed wrapper even if the agent is already available")
  .option("--dry-run", "Print the planned activation step without installing anything")
  .action(runActivateCommand);

program
  .command("activate")
  .description("Install an ACP agent")
  .argument("[agentId]", "Registry agent ID, such as codex-acp or cursor")
  .option("--force", "Reinstall the managed wrapper even if the agent is already available")
  .option("--dry-run", "Print the planned activation step without installing anything")
  .action(runActivateCommand);

if (process.argv.length <= 2) {
  program.outputHelp();
  process.exit(0);
}

program.parseAsync(process.argv).catch((error: unknown) => {
  logger.error("cli command failed", { error: serializeError(error) });
  if (isVerboseLoggingEnabled()) {
    console.error(error instanceof Error ? error.stack ?? error.message : String(error));
    process.exit(1);
    return;
  }
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
