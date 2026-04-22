import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { getOrRefreshCatalog } from "../../../skills/captcha-auto-skill/src/catalog/cache.mjs";
import {
  MODELSCOPE_MODELS_URL,
  fetchModelScopeCatalog,
  normalizeModelScopeCatalogPayload
} from "../../../skills/captcha-auto-skill/src/catalog/modelscope.mjs";
import { fixturePath } from "../test-helpers.mjs";

const modelscopeFixturePath = fixturePath("modelscope", "models.json");
const tempDirs = [];

afterEach(() => {
  while (tempDirs.length) {
    rmSync(tempDirs.pop(), { recursive: true, force: true });
  }
});

describe("normalizeModelScopeCatalogPayload", () => {
  it("filters denylisted and non-vision models, then ranks preferred matches first", () => {
    const payload = JSON.parse(readFileSync(modelscopeFixturePath, "utf8"));
    const entries = normalizeModelScopeCatalogPayload(payload, {
      fetchedAt: "2026-04-22T00:00:00.000Z"
    });

    expect(entries.map((entry) => entry.model)).toEqual([
      "Qwen/Qwen3.5-397B-A17B",
      "OpenGVLab/InternVL3_5-241B-A28B",
      "PaddlePaddle/ERNIE-4.5-VL-28B-A3B-PT",
      "Vendor/Fresh-Vision-99B"
    ]);
    expect(entries.every((entry) => entry.provider === "modelscope")).toBe(true);
    expect(entries.every((entry) => entry.source === MODELSCOPE_MODELS_URL)).toBe(true);
    expect(entries.every((entry) => entry.supportsVision === true)).toBe(true);
  });
});

describe("getOrRefreshCatalog", () => {
  it("reuses the cache until TTL expires", async () => {
    const cacheDir = mkdtempSync(path.join(os.tmpdir(), "captcha-auto-cache-"));
    tempDirs.push(cacheDir);
    let loadCount = 0;

    const first = await getOrRefreshCatalog({
      cacheDir,
      cacheKey: "modelscope",
      ttlSeconds: 3600,
      now: () => 1_000,
      loader: async () => {
        loadCount += 1;
        return [{ model: "first" }];
      }
    });
    const second = await getOrRefreshCatalog({
      cacheDir,
      cacheKey: "modelscope",
      ttlSeconds: 3600,
      now: () => 1_100,
      loader: async () => {
        loadCount += 1;
        return [{ model: "second" }];
      }
    });
    const third = await getOrRefreshCatalog({
      cacheDir,
      cacheKey: "modelscope",
      ttlSeconds: 10,
      now: () => 2_000,
      loader: async () => {
        loadCount += 1;
        return [{ model: "third" }];
      }
    });

    expect(loadCount).toBe(2);
    expect(first.items).toEqual([{ model: "first" }]);
    expect(second.items).toEqual([{ model: "first" }]);
    expect(third.items).toEqual([{ model: "third" }]);
  });

  it("bypasses the cache when refresh is requested", async () => {
    const cacheDir = mkdtempSync(path.join(os.tmpdir(), "captcha-auto-cache-"));
    tempDirs.push(cacheDir);
    let loadCount = 0;

    await getOrRefreshCatalog({
      cacheDir,
      cacheKey: "modelscope",
      ttlSeconds: 3600,
      now: () => 1_000,
      loader: async () => {
        loadCount += 1;
        return [{ model: "first" }];
      }
    });

    const refreshed = await getOrRefreshCatalog({
      cacheDir,
      cacheKey: "modelscope",
      ttlSeconds: 3600,
      now: () => 1_001,
      refresh: true,
      loader: async () => {
        loadCount += 1;
        return [{ model: "refreshed" }];
      }
    });

    expect(loadCount).toBe(2);
    expect(refreshed.items).toEqual([{ model: "refreshed" }]);
  });
});

describe("fetchModelScopeCatalog", () => {
  it("loads a live-style payload via fetch", async () => {
    const payload = JSON.parse(readFileSync(modelscopeFixturePath, "utf8"));
    const entries = await fetchModelScopeCatalog({
      fetchImpl: async () => ({
        ok: true,
        async json() {
          return payload;
        }
      }),
      fetchedAt: "2026-04-22T00:00:00.000Z"
    });

    expect(entries[0].model).toBe("Qwen/Qwen3.5-397B-A17B");
  });
});
