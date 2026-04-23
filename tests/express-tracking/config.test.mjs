import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { loadConfig } from "../../skills/express-tracking/src/config.mjs";
import { cleanupDir, makeTempDir } from "./test-helpers.mjs";

test("loadConfig reads the nearest .env.local, honors shell overrides, and accepts --recent-limit", () => {
  const tempDir = makeTempDir("express-tracking-config-");
  try {
    const projectDir = path.join(tempDir, "project");
    const nestedDir = path.join(projectDir, "nested", "child");
    mkdirSync(nestedDir, { recursive: true });

    const envFile = [
      "EXPRESS_TRACKING_KUAIDI100_KEY=file-key",
      "EXPRESS_TRACKING_KUAIDI100_CUSTOMER=file-customer",
      "EXPRESS_TRACKING_DEFAULT_RECENT_LIMIT=4"
    ].join("\n");

    writeFileSync(path.join(projectDir, ".env.local"), `${envFile}\n`, "utf8");

    const config = loadConfig({
      argv: ["--number=JDVE17645695946", "--recent-limit=1"],
      cwd: nestedDir,
      env: {
        EXPRESS_TRACKING_KUAIDI100_KEY: "shell-key"
      }
    });

    assert.equal(config.number, "JDVE17645695946");
    assert.equal(config.recentLimit, 1);
    assert.equal(config.kuaidi100.key, "shell-key");
    assert.equal(config.kuaidi100.customer, "file-customer");
  } finally {
    cleanupDir(tempDir);
  }
});

test("loadConfig rejects secret credential flags on the command line", () => {
  assert.throws(
    () => loadConfig({ argv: ["--number=JDVE17645695946", "--key=secret"] }),
    /不要通过命令行传入凭据/
  );
});
