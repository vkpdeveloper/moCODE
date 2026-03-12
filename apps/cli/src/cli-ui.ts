import * as prompts from "@clack/prompts";

type AgentChoice = {
  id: string;
  name: string;
};

type TaskSnapshot = {
  progress: number;
  stage: string;
  message: string;
};

type TaskOptions<T> = {
  taskLabel: string;
  task: (update: (snapshot: TaskSnapshot) => void) => Promise<T>;
  isFailure?: (result: T) => boolean;
  formatSuccess: (result: T) => string;
  formatError: (error: unknown) => string;
};

export function buildSelectOptions(items: AgentChoice[]) {
  return items.map((item) => ({
    label: item.name,
    value: item.id,
  }));
}

function ensureTty() {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error("Interactive mode requires a TTY.");
  }
}

export async function selectAgent(options: {
  message: string;
  items: AgentChoice[];
}) {
  ensureTty();

  if (options.items.length === 0) {
    prompts.log.info("No agents available.");
    return null;
  }

  const selected = await prompts.select({
    message: options.message,
    options: buildSelectOptions(options.items),
  });

  if (prompts.isCancel(selected)) {
    return null;
  }

  return selected as string;
}

export async function confirmUninstall(agentName: string) {
  ensureTty();
  prompts.log.info(agentName);

  const confirmed = await prompts.confirm({
    message: "Remove this managed ACP agent?",
    initialValue: false,
  });

  if (prompts.isCancel(confirmed) || !confirmed) {
    return false;
  }

  return true;
}

export function showInstalledAgents(items: AgentChoice[]) {
  if (items.length === 0) {
    console.log("No ACP agents installed.");
    return;
  }

  for (const item of items) {
    console.log(item.name);
  }
}

export async function runTask<T>(options: TaskOptions<T>) {
  ensureTty();
  const spinner = prompts.spinner();
  spinner.start(options.taskLabel);

  try {
    const result = await options.task(() => {});
    const isFailure = options.isFailure?.(result) ?? false;
    const message = options.formatSuccess(result);

    spinner.stop(isFailure ? "Failed" : "Done");
    if (isFailure) {
      prompts.log.error(message);
    } else {
      prompts.log.success(message);
    }
    return result;
  } catch (error) {
    spinner.stop("Failed");
    prompts.log.error(options.formatError(error));
    throw error;
  }
}

export function showResult(message: string, tone: "success" | "danger") {
  if (tone === "success") {
    prompts.log.success(message);
    return;
  }

  prompts.log.error(message);
}
