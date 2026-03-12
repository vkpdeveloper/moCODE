import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { randomUUID } from "node:crypto";

type TerminalRecord = {
  id: string;
  process: ChildProcessWithoutNullStreams;
  output: string;
  truncated: boolean;
  outputByteLimit: number;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  waitForExit: Promise<{ exitCode: number | null; signal: string | null }>;
};

function trimOutput(output: string, limit: number) {
  const buffer = Buffer.from(output, "utf8");
  if (buffer.length <= limit) {
    return { output, truncated: false };
  }
  const sliced = buffer.subarray(buffer.length - limit);
  return { output: sliced.toString("utf8"), truncated: true };
}

export class TerminalManager {
  private readonly terminals = new Map<string, TerminalRecord>();

  async createTerminal(params: {
    command: string;
    args?: string[];
    cwd?: string | null;
    env?: Array<{ name: string; value: string }>;
    outputByteLimit?: number | null;
  }) {
    const id = randomUUID();
    const envObject: Record<string, string> = { ...process.env } as Record<string, string>;
    for (const item of params.env ?? []) {
      envObject[item.name] = item.value;
    }

    const child = spawn(params.command, params.args ?? [], {
      cwd: params.cwd ?? process.cwd(),
      env: envObject,
      stdio: "pipe",
    });

    const outputByteLimit = params.outputByteLimit ?? 64 * 1024;

    let resolveWait: (value: { exitCode: number | null; signal: string | null }) => void = () => undefined;
    const waitForExit = new Promise<{ exitCode: number | null; signal: string | null }>((resolve) => {
      resolveWait = resolve;
    });

    const record: TerminalRecord = {
      id,
      process: child,
      output: "",
      truncated: false,
      outputByteLimit,
      exitCode: null,
      signal: null,
      waitForExit,
    };

    const onChunk = (chunk: Buffer | string) => {
      const text = typeof chunk === "string" ? chunk : chunk.toString("utf8");
      const result = trimOutput(record.output + text, outputByteLimit);
      record.output = result.output;
      record.truncated = result.truncated;
    };

    child.stdout.on("data", onChunk);
    child.stderr.on("data", onChunk);
    child.on("exit", (exitCode, signal) => {
      record.exitCode = exitCode;
      record.signal = signal;
      resolveWait({ exitCode, signal });
    });

    this.terminals.set(id, record);
    return { terminalId: id };
  }

  async terminalOutput(terminalId: string) {
    const terminal = this.getTerminal(terminalId);
    return {
      output: terminal.output,
      truncated: terminal.truncated,
      exitStatus:
        terminal.exitCode !== null || terminal.signal !== null
          ? { exitCode: terminal.exitCode, signal: terminal.signal }
          : null,
    };
  }

  async waitForExit(terminalId: string) {
    const terminal = this.getTerminal(terminalId);
    return await terminal.waitForExit;
  }

  async killTerminal(terminalId: string) {
    const terminal = this.getTerminal(terminalId);
    terminal.process.kill("SIGTERM");
    return {};
  }

  async releaseTerminal(terminalId: string) {
    const terminal = this.getTerminal(terminalId);
    if (terminal.exitCode === null && terminal.signal === null) {
      terminal.process.kill("SIGTERM");
    }
    this.terminals.delete(terminalId);
    return {};
  }

  private getTerminal(terminalId: string) {
    const terminal = this.terminals.get(terminalId);
    if (!terminal) {
      throw new Error(`Unknown terminal: ${terminalId}`);
    }
    return terminal;
  }
}
