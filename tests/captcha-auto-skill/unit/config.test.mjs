import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  DASHSCOPE_DEFAULT_MODEL,
  MODELSCOPE_DENYLIST,
  MODELSCOPE_PREFERRED_MODELS
} from "../../../skills/captcha-auto-skill/src/model-preferences.mjs";
import { DEFAULT_PROFILE, loadConfig } from "../../../skills/captcha-auto-skill/src/config.mjs";

const tempDirs = [];

function makeTempProject() {
  const tempDir = mkdtempSync(path.join(os.tmpdir(), "captcha-auto-config-"));
  tempDirs.push(tempDir);
  return tempDir;
}

afterEach(() => {
  while (tempDirs.length) {
    rmSync(tempDirs.pop(), { recursive: true, force: true });
  }
});

describe("config", () => {
  it("defaults to free-first profile", () => {
    const config = loadConfig({
      argv: ["--url=https://example.com"],
      cwd: process.cwd(),
      env: {}
    });

    expect(DEFAULT_PROFILE).toBe("free-first");
    expect(config.profile).toBe("free-first");
  });

  it("loads project .env.local by walking up from cwd", () => {
    const projectRoot = makeTempProject();
    const nestedDir = path.join(projectRoot, "deep", "nested");
    mkdirSync(nestedDir, { recursive: true });
    writeFileSync(
      path.join(projectRoot, ".env.local"),
      "CAPTCHA_MODELSCOPE_API_KEY=from-project\nCAPTCHA_DEFAULT_PROFILE=paid-latest\n",
      "utf8"
    );

    const config = loadConfig({
      argv: ["--url=https://example.com"],
      cwd: nestedDir,
      env: {}
    });

    expect(config.modelscope.apiKey).toBe("from-project");
    expect(config.profile).toBe("paid-latest");
  });

  it("prefers process env over .env.local", () => {
    const projectRoot = makeTempProject();
    writeFileSync(
      path.join(projectRoot, ".env.local"),
      "CAPTCHA_MODELSCOPE_API_KEY=from-file\n",
      "utf8"
    );

    const config = loadConfig({
      argv: ["--url=https://example.com"],
      cwd: projectRoot,
      env: { CAPTCHA_MODELSCOPE_API_KEY: "from-env" }
    });

    expect(config.modelscope.apiKey).toBe("from-env");
  });

  it("rejects api-key flags", () => {
    expect(() =>
      loadConfig({
        argv: ["--url=https://example.com", "--api-key=secret"],
        cwd: process.cwd(),
        env: {}
      })
    ).toThrow(/--api-key/);
  });

  it("accepts a direct input path for candidate-answer generation", () => {
    const projectRoot = makeTempProject();

    const config = loadConfig({
      argv: ["--input=fixtures/captcha/simple.svg"],
      cwd: projectRoot,
      env: {}
    });

    expect(config.url).toBeNull();
    expect(config.inputPath).toBe(path.join(projectRoot, "fixtures", "captcha", "simple.svg"));
  });

  it("locks denylist and seeded model preferences", () => {
    expect(MODELSCOPE_DENYLIST).toEqual([
      "Qwen/Qwen3-VL-8B-Instruct",
      "Qwen/Qwen3-VL-235B-A22B-Instruct"
    ]);
    expect(MODELSCOPE_PREFERRED_MODELS).toEqual([
      "Qwen/Qwen3.5-397B-A17B",
      "OpenGVLab/InternVL3_5-241B-A28B",
      "PaddlePaddle/ERNIE-4.5-VL-28B-A3B-PT"
    ]);
    expect(DASHSCOPE_DEFAULT_MODEL).toBe("qwen3.6-plus");
  });
});
