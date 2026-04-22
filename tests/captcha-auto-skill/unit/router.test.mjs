import { describe, expect, it } from "vitest";

import { buildRoutePlan } from "../../../skills/captcha-auto-skill/src/router.mjs";

const modelscopeCatalog = [
  { provider: "modelscope", model: "Qwen/Qwen3.5-397B-A17B" },
  { provider: "modelscope", model: "OpenGVLab/InternVL3_5-241B-A28B" }
];

const dashscopeCatalog = [
  { provider: "dashscope", model: "qwen3.6-plus" },
  { provider: "dashscope", model: "qwen3.6-plus-2026-04-02" }
];

describe("buildRoutePlan", () => {
  it("builds the free-first chain as local OCR -> DashScope", () => {
    const plan = buildRoutePlan({
      profile: "free-first",
      modelscopeCatalog,
      dashscopeCatalog
    });

    expect(plan).toEqual([
      { kind: "local_ocr" },
      { kind: "remote", provider: "dashscope", model: "qwen3.6-plus" }
    ]);
  });

  it("builds the paid-latest chain as local OCR -> DashScope", () => {
    const plan = buildRoutePlan({
      profile: "paid-latest",
      modelscopeCatalog,
      dashscopeCatalog
    });

    expect(plan).toEqual([
      { kind: "local_ocr" },
      { kind: "remote", provider: "dashscope", model: "qwen3.6-plus" }
    ]);
  });

  it("uses explicit provider and model overrides after local OCR", () => {
    const plan = buildRoutePlan({
      profile: "free-first",
      provider: "modelscope",
      model: "Qwen/Qwen3.5-397B-A17B",
      modelscopeCatalog,
      dashscopeCatalog
    });

    expect(plan).toEqual([
      { kind: "local_ocr" },
      { kind: "remote", provider: "modelscope", model: "Qwen/Qwen3.5-397B-A17B" }
    ]);
  });

  it("rejects denylisted explicit model overrides", () => {
    expect(() =>
      buildRoutePlan({
        profile: "free-first",
        provider: "modelscope",
        model: "Qwen/Qwen3-VL-8B-Instruct",
        modelscopeCatalog,
        dashscopeCatalog
      })
    ).toThrow(/denylisted/i);
  });

  it("rejects ModelScope-style model overrides unless the provider is explicit", () => {
    expect(() =>
      buildRoutePlan({
        profile: "free-first",
        model: "Qwen/Qwen3.5-397B-A17B",
        modelscopeCatalog,
        dashscopeCatalog
      })
    ).toThrow(/provider=modelscope/i);
  });
});
