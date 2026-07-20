#!/usr/bin/env node

import { spawn } from "node:child_process";
import process from "node:process";
import readline from "node:readline";

const options = parseArgs(process.argv.slice(2));
const mode = options.send ? "send" : "dry-run";

if (!options.threadId) fail("Usage: send-message.mjs --thread-id <UUID> --message <TEXT> [--send --confirm-send]");
if (!options.message) fail("--message is required");
if (options.send && !options.confirmSend) {
  fail("真实发送需要同时提供 --send 和 --confirm-send；默认只执行 Dry Run");
}

const child = spawn("codex", ["app-server", "--stdio"], {
  cwd: process.env.HOME,
  stdio: ["pipe", "pipe", "pipe"],
});

const result = {
  mode,
  threadId: options.threadId,
  initialized: false,
  resumed: false,
  turnStarted: false,
  completed: false,
  error: null,
};
let nextId = 1;
let finished = false;
const stdout = readline.createInterface({ input: child.stdout });

stdout.on("line", (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }

  if (message.id === 1) {
    if (message.error) return finishWithError(message.error.message ?? "initialize failed");
    result.initialized = true;
    send({ method: "initialized" });
    send({
      id: 2,
      method: "thread/resume",
      params: { threadId: options.threadId, excludeTurns: true },
    });
    return;
  }

  if (message.id === 2) {
    if (message.error) return finishWithError(message.error.message ?? "thread/resume failed");
    result.resumed = true;
    if (!options.send) return finish();
    send({
      id: 3,
      method: "turn/start",
      params: {
        threadId: options.threadId,
        input: [{ type: "text", text: options.message }],
      },
    });
    return;
  }

  if (message.id === 3) {
    if (message.error) return finishWithError(message.error.message ?? "turn/start failed");
    result.turnStarted = true;
    return;
  }

  if (message.method === "turn/completed") {
    result.completed = true;
    return finish();
  }

  if (message.method === "error") {
    return finishWithError("server reported an error");
  }
});

child.on("error", (error) => finishWithError(error.message));
child.on("exit", () => {
  if (!finished) finish();
});

send({
  id: nextId++,
  method: "initialize",
  params: {
    clientInfo: { name: "threadbeacon-send-message-poc", version: "0.1" },
    capabilities: { experimentalApi: true },
  },
});

function send(message) {
  child.stdin.write(`${JSON.stringify(message)}\n`);
}

function finishWithError(message) {
  result.error = message;
  finish();
}

function finish() {
  if (finished) return;
  finished = true;
  stdout.close();
  child.stdin.end();
  child.kill("SIGTERM");
  console.log(JSON.stringify(result, null, 2));
  if (result.error) process.exitCode = 1;
}

function parseArgs(args) {
  const result = { send: false, confirmSend: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--thread-id") result.threadId = args[++index];
    else if (arg === "--message") result.message = args[++index];
    else if (arg === "--send") result.send = true;
    else if (arg === "--confirm-send") result.confirmSend = true;
    else fail(`Unknown argument: ${arg}`);
  }
  return result;
}

function fail(message) {
  console.error(message);
  process.exit(2);
}
