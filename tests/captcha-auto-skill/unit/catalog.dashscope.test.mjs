import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  DASHSCOPE_VISION_DOCS_URL,
  DASHSCOPE_FALLBACK_MODELS,
  fetchDashScopeCatalog,
  parseDashScopeVisionModels
} from "../../../skills/captcha-auto-skill/src/catalog/dashscope.mjs";
import { fixturePath } from "../test-helpers.mjs";

const dashscopeFixturePath = fixturePath("dashscope", "vision-model.html");

describe("parseDashScopeVisionModels", () => {
  it("extracts qwen3.6 vision entries from docs html", () => {
    const html = readFileSync(dashscopeFixturePath, "utf8");
    const entries = parseDashScopeVisionModels(html, {
      fetchedAt: "2026-04-22T00:00:00.000Z"
    });

    expect(entries.map((entry) => entry.model)).toEqual([
      "qwen3.6-plus",
      "qwen3.6-plus-2026-04-02",
      "qwen3.6-flash",
      "qwen-vl-ocr"
    ]);
    expect(entries.every((entry) => entry.provider === "dashscope")).toBe(true);
    expect(entries.every((entry) => entry.source === DASHSCOPE_VISION_DOCS_URL)).toBe(true);
  });
});

describe("fetchDashScopeCatalog", () => {
  it("falls back to the alias table when docs parsing yields nothing", async () => {
    const entries = await fetchDashScopeCatalog({
      fetchImpl: async () => ({
        ok: true,
        async text() {
          return "<html><body>no models here</body></html>";
        }
      }),
      fetchedAt: "2026-04-22T00:00:00.000Z"
    });

    expect(entries.map((entry) => entry.model)).toEqual(
      DASHSCOPE_FALLBACK_MODELS.map((entry) => entry.model)
    );
  });
});
