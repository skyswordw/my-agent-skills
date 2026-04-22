import { mkdirSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  OCR_CONFIDENCE_THRESHOLD,
  runLocalOcr
} from "../../../skills/captcha-auto-skill/src/ocr/local.mjs";
import { preprocessCaptchaImage } from "../../../skills/captcha-auto-skill/src/ocr/preprocess.mjs";
import { fixturePath } from "../test-helpers.mjs";

const fixturesDir = fixturePath("captcha");
const tempDirs = [];

function makeTempDir() {
  const dir = path.join(
    os.tmpdir(),
    `captcha-auto-ocr-${Date.now()}-${Math.random().toString(16).slice(2)}`
  );
  mkdirSync(dir, { recursive: true });
  tempDirs.push(dir);
  return dir;
}

function makeWorkerFactory({ text, confidence }) {
  return async () => ({
    async recognize() {
      return {
        data: {
          text,
          confidence
        }
      };
    },
    async terminate() {}
  });
}

afterEach(() => {
  while (tempDirs.length) {
    rmSync(tempDirs.pop(), { recursive: true, force: true });
  }
});

describe("preprocessCaptchaImage", () => {
  it("rescales and binarizes captcha images", async () => {
    const inputPath = path.join(fixturesDir, "simple.svg");
    const result = await preprocessCaptchaImage({ inputPath, scale: 2 });

    expect(result.metadata).toEqual({
      format: "png",
      width: 240,
      height: 88
    });
    expect(result.buffer.subarray(0, 8)).toEqual(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    );
  });
});

describe("runLocalOcr", () => {
  it("sanitizes recognized text to uppercase alphanumeric output", async () => {
    const result = await runLocalOcr({
      inputPath: path.join(fixturesDir, "simple.svg"),
      workerFactory: makeWorkerFactory({ text: " aB-1 2 \n", confidence: 98 })
    });

    expect(result).toMatchObject({
      success: true,
      text: "AB12",
      method: "local_ocr",
      shouldShortCircuit: true
    });
    expect(result.confidence).toBe(98);
  });

  it("solves arithmetic captcha text before returning", async () => {
    const result = await runLocalOcr({
      inputPath: path.join(fixturesDir, "simple.svg"),
      workerFactory: makeWorkerFactory({ text: "15 + 5 =", confidence: 98 })
    });

    expect(result).toMatchObject({
      success: true,
      text: "20",
      method: "local_ocr",
      shouldShortCircuit: true
    });
  });

  it("fails when confidence falls below the threshold", async () => {
    const result = await runLocalOcr({
      inputPath: path.join(fixturesDir, "simple.svg"),
      workerFactory: makeWorkerFactory({
        text: "AB12",
        confidence: OCR_CONFIDENCE_THRESHOLD - 1
      })
    });

    expect(result).toMatchObject({
      success: false,
      text: null,
      shouldShortCircuit: false,
      reason: "low_confidence"
    });
  });

  it("fails when sanitized text is empty", async () => {
    const result = await runLocalOcr({
      inputPath: path.join(fixturesDir, "noisy.svg"),
      workerFactory: makeWorkerFactory({
        text: " \n-_* ",
        confidence: 99
      })
    });

    expect(result).toMatchObject({
      success: false,
      text: null,
      shouldShortCircuit: false,
      reason: "empty_text"
    });
  });
});
