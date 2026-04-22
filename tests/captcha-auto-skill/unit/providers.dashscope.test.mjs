import { describe, expect, it, vi } from "vitest";

import { runDashScopeVisionInference } from "../../../skills/captcha-auto-skill/src/providers/dashscope.mjs";

const sampleImage = Buffer.from("sample-image");

describe("runDashScopeVisionInference", () => {
  it("fails fast with a clear config error when the api key is missing", async () => {
    const fetchImpl = vi.fn();

    const result = await runDashScopeVisionInference({
      apiKey: null,
      model: "qwen3.6-plus",
      imageBuffer: sampleImage,
      fetchImpl
    });

    expect(fetchImpl).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      success: false,
      resolvedProvider: "dashscope",
      resolvedModel: "qwen3.6-plus",
      retryable: false,
      reason: "missing_api_key"
    });
    expect(result.message).toMatch(/CAPTCHA_DASHSCOPE_API_KEY/);
  });

  it("sends a cropped-image multimodal request and normalizes a successful response", async () => {
    let capturedBody = null;
    const result = await runDashScopeVisionInference({
      apiKey: "secret",
      model: "qwen3.6-plus",
      imageBuffer: sampleImage,
      fetchImpl: async (_url, options) => {
        capturedBody = JSON.parse(options.body);
        return {
          ok: true,
          async json() {
            return {
              choices: [
                {
                  message: {
                    content: " z9x8 "
                  }
                }
              ]
            };
          }
        };
      }
    });

    expect(capturedBody.model).toBe("qwen3.6-plus");
    expect(capturedBody.messages[0].content[1].image_url.url.startsWith("data:image/png;base64,")).toBe(true);
    expect(result).toMatchObject({
      success: true,
      text: "Z9X8",
      resolvedProvider: "dashscope",
      resolvedModel: "qwen3.6-plus"
    });
  });

  it("solves arithmetic captcha text returned by the model", async () => {
    const result = await runDashScopeVisionInference({
      apiKey: "secret",
      model: "qwen3.6-plus",
      imageBuffer: sampleImage,
      fetchImpl: async () => ({
        ok: true,
        async json() {
          return {
            choices: [
              {
                message: {
                  content: "15+5="
                }
              }
            ]
          };
        }
      })
    });

    expect(result).toMatchObject({
      success: true,
      text: "20",
      resolvedProvider: "dashscope",
      resolvedModel: "qwen3.6-plus"
    });
  });

  it("returns a retryable transport failure", async () => {
    const result = await runDashScopeVisionInference({
      apiKey: "secret",
      model: "qwen3.6-plus",
      imageBuffer: sampleImage,
      fetchImpl: async () => {
        throw new Error("bad gateway");
      }
    });

    expect(result).toMatchObject({
      success: false,
      retryable: true,
      reason: "transport_error"
    });
  });

  it("returns a retryable failure when the provider responds with no choices", async () => {
    const result = await runDashScopeVisionInference({
      apiKey: "secret",
      model: "qwen3.6-plus",
      imageBuffer: sampleImage,
      fetchImpl: async () => ({
        ok: true,
        async json() {
          return { choices: [] };
        }
      })
    });

    expect(result).toMatchObject({
      success: false,
      retryable: true,
      reason: "empty_choice"
    });
  });
});
