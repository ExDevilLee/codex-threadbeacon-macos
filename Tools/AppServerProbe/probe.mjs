#!/usr/bin/env node

import { spawn } from "node:child_process";
import process from "node:process";
import readline from "node:readline";

const watchSeconds = parseWatchSeconds(process.argv.slice(2));
const child = spawn("codex", ["app-server", "--stdio"], {
  cwd: process.env.HOME,
  stdio: ["pipe", "pipe", "pipe"],
});

const result = {
  initialized: false,
  listedThreads: [],
  loadedThreadIDs: [],
  readThread: null,
  notifications: [],
  serverRequests: [],
  stderrCategories: [],
};
const pendingResponses = new Set([1, 2, 3, 4]);
let finished = false;

const stdout = readline.createInterface({ input: child.stdout });
const stderr = readline.createInterface({ input: child.stderr });

stdout.on("line", (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }

  if (message.id === 1 && message.result) {
    result.initialized = true;
    pendingResponses.delete(1);
    send({ method: "initialized" });
    send({
      id: 2,
      method: "thread/list",
      params: {
        limit: 20,
        sortKey: "updated_at",
        sortDirection: "desc",
        useStateDbOnly: true,
      },
    });
    send({ id: 3, method: "thread/loaded/list", params: { limit: 100 } });
    return;
  }

  if (message.id === 2) {
    pendingResponses.delete(2);
    result.listedThreads = (message.result?.data ?? []).map((thread) => ({
      id: thread.id,
      parentThreadId: thread.parentThreadId ?? null,
      source: sourceKind(thread.source),
      status: thread.status?.type ?? "unknown",
    }));
    const firstThreadID = message.result?.data?.[0]?.id;
    if (firstThreadID) {
      send({
        id: 4,
        method: "thread/read",
        params: { threadId: firstThreadID, includeTurns: false },
      });
    } else {
      pendingResponses.delete(4);
    }
    scheduleFinishIfReady();
    return;
  }

  if (message.id === 3) {
    pendingResponses.delete(3);
    result.loadedThreadIDs = message.result?.data ?? [];
    scheduleFinishIfReady();
    return;
  }

  if (message.id === 4) {
    pendingResponses.delete(4);
    const thread = message.result?.thread;
    result.readThread = thread
      ? {
          id: thread.id,
          source: sourceKind(thread.source),
          status: thread.status?.type ?? "unknown",
          turnCount: thread.turns?.length ?? 0,
        }
      : null;
    scheduleFinishIfReady();
    return;
  }

  if (message.method && Object.hasOwn(message, "id")) {
    result.serverRequests.push(sanitizeEvent(message));
    return;
  }

  if (message.method) {
    result.notifications.push(sanitizeEvent(message));
  }
});

stderr.on("line", (line) => {
  const category = line.match(/\b(ERROR|WARN)\b[^:]*:\s*([^\n]+)/)?.[1];
  if (category && !result.stderrCategories.includes(category)) {
    result.stderrCategories.push(category);
  }
});

child.on("error", (error) => {
  console.error(JSON.stringify({ error: error.message }));
  process.exitCode = 1;
});

child.on("exit", () => {
  if (!finished) {
    finish();
  }
});

send({
  id: 1,
  method: "initialize",
  params: {
    clientInfo: { name: "threadbeacon-app-server-probe", version: "0.1" },
    capabilities: { experimentalApi: true },
  },
});

function send(message) {
  child.stdin.write(`${JSON.stringify(message)}\n`);
}

function scheduleFinishIfReady() {
  if (pendingResponses.size > 0) return;
  setTimeout(finish, watchSeconds * 1_000);
}

function finish() {
  if (finished) return;
  finished = true;
  stdout.close();
  stderr.close();
  child.stdin.end();
  child.kill("SIGTERM");
  console.log(JSON.stringify(result, null, 2));
}

function sanitizeEvent(message) {
  const params = message.params ?? {};
  return {
    method: message.method,
    threadId: params.threadId ?? null,
    turnId: params.turnId ?? params.turn?.id ?? null,
    willRetry: params.willRetry ?? null,
    status: params.status?.type ?? params.turn?.status ?? null,
  };
}

function sourceKind(source) {
  if (typeof source === "string") return source;
  if (!source || typeof source !== "object") return "unknown";
  return source.type ?? Object.keys(source)[0] ?? "unknown";
}

function parseWatchSeconds(args) {
  const index = args.indexOf("--watch-seconds");
  if (index === -1) return 0;
  const value = Number(args[index + 1]);
  if (!Number.isFinite(value) || value < 0 || value > 300) {
    throw new Error("--watch-seconds must be between 0 and 300");
  }
  return value;
}
