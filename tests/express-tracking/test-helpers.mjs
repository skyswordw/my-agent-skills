import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { createServer } from "node:http";

export const repoRoot = path.resolve(import.meta.dirname, "..", "..");
export const skillRoot = path.join(repoRoot, "skills", "express-tracking");
export const scriptPath = path.join(skillRoot, "scripts", "run.mjs");
export const installScriptPath = path.join(repoRoot, "scripts", "install-codex-skill.sh");
export const fixtureDir = path.join(repoRoot, "tests", "express-tracking", "fixtures");

export function makeTempDir(prefix) {
  return mkdtempSync(path.join(tmpdir(), prefix));
}

export function cleanupDir(dirPath) {
  rmSync(dirPath, { recursive: true, force: true });
}

export function readFixture(name) {
  return readFileSync(path.join(fixtureDir, name), "utf8");
}

export function writeEnvLocal(projectDir, values) {
  const lines = Object.entries(values).map(([key, value]) => `${key}=${value}`);
  writeFileSync(path.join(projectDir, ".env.local"), `${lines.join("\n")}\n`, "utf8");
}

export function runCli({ cwd, args = [], env = {} }) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [scriptPath, ...args], {
      cwd,
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });

    child.on("error", reject);
    child.on("close", (status) => {
      resolve({
        status,
        stdout,
        stderr
      });
    });
  });
}

export async function startMockKuaidi100Server({
  autoPayload,
  queryPayload,
  autoStatus = 200,
  queryStatus = 200
}) {
  const requests = {
    auto: [],
    query: []
  };

  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    if (request.method === "GET" && url.pathname === "/autonumber/auto") {
      requests.auto.push({
        url
      });
      response.writeHead(autoStatus, { "Content-Type": "application/json; charset=utf-8" });
      response.end(JSON.stringify(autoPayload));
      return;
    }

    if (request.method === "POST" && url.pathname === "/poll/query.do") {
      const chunks = [];
      for await (const chunk of request) {
        chunks.push(chunk);
      }
      const body = Buffer.concat(chunks).toString("utf8");
      const form = new URLSearchParams(body);
      requests.query.push({
        body,
        form
      });
      response.writeHead(queryStatus, { "Content-Type": "application/json; charset=utf-8" });
      response.end(JSON.stringify(queryPayload));
      return;
    }

    response.writeHead(404);
    response.end();
  });

  await new Promise((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });

  const address = server.address();
  assert.ok(address && typeof address === "object");

  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    requests,
    async close() {
      await new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    }
  };
}
