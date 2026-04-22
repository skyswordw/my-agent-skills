import { afterEach, describe, expect, it, vi } from "vitest";
import { fixturePath } from "../test-helpers.mjs";

afterEach(() => {
  vi.resetModules();
  vi.clearAllMocks();
  vi.doUnmock("../../../skills/captcha-auto-skill/src/catalog/modelscope.mjs");
  vi.doUnmock("../../../skills/captcha-auto-skill/src/catalog/dashscope.mjs");
  vi.doUnmock("../../../skills/captcha-auto-skill/src/catalog/cache.mjs");
  vi.doUnmock("../../../skills/captcha-auto-skill/src/router.mjs");
});

describe("runCaptchaFlow catalog loading", () => {
  it("does not load remote catalogs for candidate generation when local OCR succeeds", async () => {
    const fetchModelScopeCatalog = vi.fn(async () => [
      { provider: "modelscope", model: "Qwen/Qwen3.5-397B-A17B" }
    ]);
    const fetchDashScopeCatalog = vi.fn(async () => [
      { provider: "dashscope", model: "qwen3.6-plus" }
    ]);

    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/modelscope.mjs", () => ({
      fetchModelScopeCatalog
    }));
    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/dashscope.mjs", () => ({
      fetchDashScopeCatalog
    }));

    const { runCaptchaCandidate } = await import("../../../skills/captcha-auto-skill/src/run-captcha.mjs");
    const { runCaptchaRouter } = await import("../../../skills/captcha-auto-skill/src/router.mjs");

    const result = await runCaptchaCandidate({
      inputPath: fixturePath("captcha", "simple.svg"),
      runRouter: async (input) => runCaptchaRouter(input)
    });

    expect(result.success).toBe(true);
    expect(fetchDashScopeCatalog).not.toHaveBeenCalled();
    expect(fetchModelScopeCatalog).not.toHaveBeenCalled();
  });

  it("loads only the DashScope catalog for default routing even when the router is wrapped", async () => {
    const fetchModelScopeCatalog = vi.fn(async () => [
      { provider: "modelscope", model: "Qwen/Qwen3.5-397B-A17B" }
    ]);
    const fetchDashScopeCatalog = vi.fn(async () => [
      { provider: "dashscope", model: "qwen3.6-plus" }
    ]);

    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/modelscope.mjs", () => ({
      fetchModelScopeCatalog
    }));
    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/dashscope.mjs", () => ({
      fetchDashScopeCatalog
    }));

    const { runCaptchaFlow } = await import(
      "../../../skills/captcha-auto-skill/src/browser/run-captcha-flow.mjs"
    );
    const { runCaptchaRouter } = await import("../../../skills/captcha-auto-skill/src/router.mjs");

    await runCaptchaFlow({
      url: "https://example.com/login",
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
        captchaBuffer: Buffer.from("cropped"),
        fill: async () => {},
        submit: async () => {}
      }),
      runRouter: async (input) =>
        runCaptchaRouter({
          ...input,
          localOcr: async () => ({
            success: false,
            text: null,
            confidence: 12,
            method: "local_ocr",
            shouldShortCircuit: false,
            reason: "low_confidence"
          }),
          dashscopeRunner: async () => ({
            success: false,
            text: null,
            retryable: true,
            reason: "empty_choice"
          })
        })
    });

    expect(fetchDashScopeCatalog).toHaveBeenCalledTimes(1);
    expect(fetchModelScopeCatalog).not.toHaveBeenCalled();
  });

  it("loads only the ModelScope catalog when the provider override is explicit even when the router is wrapped", async () => {
    const fetchModelScopeCatalog = vi.fn(async () => [
      { provider: "modelscope", model: "Qwen/Qwen3.5-397B-A17B" }
    ]);
    const fetchDashScopeCatalog = vi.fn(async () => [
      { provider: "dashscope", model: "qwen3.6-plus" }
    ]);

    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/modelscope.mjs", () => ({
      fetchModelScopeCatalog
    }));
    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/dashscope.mjs", () => ({
      fetchDashScopeCatalog
    }));

    const { runCaptchaFlow } = await import(
      "../../../skills/captcha-auto-skill/src/browser/run-captcha-flow.mjs"
    );
    const { runCaptchaRouter } = await import("../../../skills/captcha-auto-skill/src/router.mjs");

    await runCaptchaFlow({
      url: "https://example.com/login",
      provider: "modelscope",
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
        captchaBuffer: Buffer.from("cropped"),
        fill: async () => {},
        submit: async () => {}
      }),
      runRouter: async (input) =>
        runCaptchaRouter({
          ...input,
          localOcr: async () => ({
            success: false,
            text: null,
            confidence: 12,
            method: "local_ocr",
            shouldShortCircuit: false,
            reason: "low_confidence"
          }),
          modelscopeRunner: async () => ({
            success: false,
            text: null,
            retryable: true,
            reason: "empty_choice"
          })
        })
    });

    expect(fetchModelScopeCatalog).toHaveBeenCalledTimes(1);
    expect(fetchDashScopeCatalog).not.toHaveBeenCalled();
  });
});

describe("runCaptchaRouter catalog cache controls", () => {
  it("passes refresh and TTL settings into runtime catalog loading", async () => {
    const getOrRefreshCatalog = vi.fn(async ({ loader }) => ({
      fetchedAtEpoch: 1_000,
      items: await loader()
    }));
    const fetchModelScopeCatalog = vi.fn(async () => [
      { provider: "modelscope", model: "Qwen/Qwen3.5-397B-A17B" }
    ]);
    const fetchDashScopeCatalog = vi.fn(async () => [
      { provider: "dashscope", model: "qwen3.6-plus" }
    ]);

    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/cache.mjs", () => ({
      getOrRefreshCatalog
    }));
    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/modelscope.mjs", () => ({
      fetchModelScopeCatalog
    }));
    vi.doMock("../../../skills/captcha-auto-skill/src/catalog/dashscope.mjs", () => ({
      fetchDashScopeCatalog
    }));

    const { runCaptchaRouter } = await import("../../../skills/captcha-auto-skill/src/router.mjs");

    await runCaptchaRouter({
      profile: "free-first",
      inputPath: fixturePath("captcha", "simple.svg"),
      imageBuffer: Buffer.from("cropped"),
      refreshCatalog: true,
      catalogTtlSeconds: 17,
      catalogCacheDir: "/tmp/captcha-runtime-cache",
      localOcr: async () => ({
        success: false,
        text: null,
        confidence: 12,
        method: "local_ocr",
        shouldShortCircuit: false,
        reason: "low_confidence"
      }),
      dashscopeRunner: async () => ({
        success: false,
        text: null,
        retryable: true,
        reason: "empty_choice"
      })
    });

    expect(getOrRefreshCatalog).toHaveBeenCalledTimes(1);
    expect(getOrRefreshCatalog).toHaveBeenCalledWith(
      expect.objectContaining({
        cacheDir: "/tmp/captcha-runtime-cache",
        cacheKey: "dashscope",
        ttlSeconds: 17,
        refresh: true
      })
    );
    expect(fetchDashScopeCatalog).toHaveBeenCalledTimes(1);
    expect(fetchModelScopeCatalog).not.toHaveBeenCalled();
  });
});
