import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import { runCaptchaFlow } from "../../../skills/captcha-auto-skill/src/browser/run-captcha-flow.mjs";
import { runCaptchaCandidate } from "../../../skills/captcha-auto-skill/src/run-captcha.mjs";
import { fixturePath } from "../test-helpers.mjs";

const tempDirs = [];

function makeTempDir() {
  const dir = mkdtempSync(path.join(os.tmpdir(), "captcha-auto-flow-"));
  tempDirs.push(dir);
  return dir;
}

afterEach(() => {
  while (tempDirs.length) {
    rmSync(tempDirs.pop(), { recursive: true, force: true });
  }
});

describe("runCaptchaFlow", () => {
  it("passes only the cropped captcha image to the router and returns a candidate answer by default", async () => {
    const fill = vi.fn(async () => {});
    const submit = vi.fn(async () => {});
    const cropped = Buffer.from("cropped-captcha");
    const full = Buffer.from("full-page");
    const captured = [];

    const result = await runCaptchaFlow({
      url: "https://example.com/login",
      artifactsDir: makeTempDir(),
      launchBrowser: async () => ({
        async newPage() {
          return {
            async goto() {},
            async screenshot() {
              return full;
            }
          };
        },
        async close() {}
      }),
      locateCaptcha: async () => ({
        captchaBuffer: cropped,
        fill,
        submit
      }),
      runRouter: async (input) => {
        captured.push(input);
        return {
          success: true,
          text: "AB12",
          method: "modelscope",
          resolvedProvider: "modelscope",
          resolvedModel: "Qwen/Qwen3.5-397B-A17B",
          fallbackChain: [],
          localConfidence: null
        };
      }
    });

    expect(captured[0].imageBuffer.equals(cropped)).toBe(true);
    expect(captured[0].imageBuffer.equals(full)).toBe(false);
    expect(existsSync(captured[0].inputPath)).toBe(false);
    expect(existsSync(path.dirname(captured[0].inputPath))).toBe(false);
    expect(fill).not.toHaveBeenCalled();
    expect(submit).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      success: true,
      text: "AB12",
      resolvedProvider: "modelscope",
      resolvedModel: "Qwen/Qwen3.5-397B-A17B"
    });
    expect(result.debugArtifacts).toEqual({});
  });

  it("fills and submits only when page actions are explicitly enabled", async () => {
    const fill = vi.fn(async () => {});
    const submit = vi.fn(async () => {});

    await runCaptchaFlow({
      url: "https://example.com/login",
      applyPageActions: true,
      artifactsDir: makeTempDir(),
      launchBrowser: async () => ({
        async newPage() {
          return {
            async goto() {},
            async screenshot() {
              return Buffer.from("full-page");
            }
          };
        },
        async close() {}
      }),
      locateCaptcha: async () => ({
        captchaBuffer: Buffer.from("cropped-captcha"),
        fill,
        submit
      }),
      runRouter: async () => ({
        success: true,
        text: "AB12",
        method: "local_ocr",
        resolvedProvider: null,
        resolvedModel: null,
        fallbackChain: [],
        localConfidence: 99
      })
    });

    expect(fill).toHaveBeenCalledWith("AB12");
    expect(submit).toHaveBeenCalledTimes(1);
  });

  it("writes full-page debug artifacts only when debug-screenshots is enabled", async () => {
    const artifactsDir = makeTempDir();
    const full = Buffer.from("full-page");
    const cropped = Buffer.from("cropped");
    const captured = [];

    const result = await runCaptchaFlow({
      url: "https://example.com/login",
      debugScreenshots: true,
      artifactsDir,
      launchBrowser: async () => ({
        async newPage() {
          return {
            async goto() {},
            async screenshot() {
              return full;
            }
          };
        },
        async close() {}
      }),
      locateCaptcha: async () => ({
        captchaBuffer: cropped,
        fill: async () => {},
        submit: async () => {}
      }),
      runRouter: async (input) => {
        captured.push(input);
        return {
          success: false,
          text: null,
          method: "none",
          resolvedProvider: null,
          resolvedModel: null,
          fallbackChain: [],
          localConfidence: null
        };
      }
    });

    expect(result.debugArtifacts.fullPage).toBeTruthy();
    expect(existsSync(result.debugArtifacts.fullPage)).toBe(true);
    expect(readFileSync(result.debugArtifacts.fullPage).equals(full)).toBe(true);
    expect(result.debugArtifacts.captchaCrop).toBeTruthy();
    expect(existsSync(result.debugArtifacts.captchaCrop)).toBe(true);
    expect(readFileSync(result.debugArtifacts.captchaCrop).equals(cropped)).toBe(true);
    expect(existsSync(captured[0].inputPath)).toBe(false);
  });
});

describe("runCaptchaCandidate", () => {
  it("generates a candidate answer from a local captcha image without browser automation", async () => {
    const captured = [];
    const inputPath = fixturePath("captcha", "simple.svg");

    const result = await runCaptchaCandidate({
      inputPath,
      runRouter: async (input) => {
        captured.push(input);
        return {
          success: true,
          text: "AB12",
          method: "local_ocr",
          resolvedProvider: null,
          resolvedModel: null,
          fallbackChain: [],
          localConfidence: 98
        };
      }
    });

    expect(captured[0].inputPath).toBe(inputPath);
    expect(Buffer.isBuffer(captured[0].imageBuffer)).toBe(true);
    expect(result).toMatchObject({
      success: true,
      text: "AB12",
      resolvedProvider: null,
      resolvedModel: null
    });
  });
});
