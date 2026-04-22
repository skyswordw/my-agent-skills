import { describe, expect, it, vi } from "vitest";

import { runModelScopeVisionInference } from "../../../skills/captcha-auto-skill/src/providers/modelscope.mjs";

const sampleImage = Buffer.from("sample-image");

describe("runModelScopeVisionInference", () => {
  it("fails fast with a clear config error when the api key is missing", async () => {
    const fetchImpl = vi.fn();

    const result = await runModelScopeVisionInference({
      apiKey: undefined,
      model: "Qwen/Qwen3.5-397B-A17B",
      imageBuffer: sampleImage,
      fetchImpl
    });

    expect(fetchImpl).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      success: false,
      resolvedProvider: "modelscope",
      resolvedModel: "Qwen/Qwen3.5-397B-A17B",
      retryable: false,
      reason: "missing_api_key"
    });
    expect(result.message).toMatch(/CAPTCHA_MODELSCOPE_API_KEY/);
  });

  it("rejects denylisted models before sending a request", async () => {
    const fetchImpl = vi.fn();

    const result = await runModelScopeVisionInference({
      apiKey: "secret",
      model: "Qwen/Qwen3-VL-8B-Instruct",
      imageBuffer: sampleImage,
      fetchImpl
    });

    expect(fetchImpl).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      success: false,
      retryable: false,
      reason: "denylisted_model"
    });
  });

  it("sends a cropped-image multimodal request and normalizes a successful response", async () => {
    const fetchImpl = vi.fn(async (_url, options) => ({
      ok: true,
      async json() {
        return {
          choices: [
            {
              message: {
                content: " ab-12 "
              }
            }
          ]
        };
      }
    }));

    const result = await runModelScopeVisionInference({
      apiKey: "secret",
      model: "Qwen/Qwen3.5-397B-A17B",
      imageBuffer: sampleImage,
      fetchImpl
    });

    const [, options] = fetchImpl.mock.calls[0];
    const body = JSON.parse(options.body);

    expect(body.model).toBe("Qwen/Qwen3.5-397B-A17B");
    expect(body.messages[0].content[1].image_url.url.startsWith("data:image/png;base64,")).toBe(true);
    expect(result).toMatchObject({
      success: true,
      text: "AB12",
      resolvedProvider: "modelscope",
      resolvedModel: "Qwen/Qwen3.5-397B-A17B"
    });
  });

  it("solves arithmetic captcha text returned by the model", async () => {
    const result = await runModelScopeVisionInference({
      apiKey: "secret",
      model: "Qwen/Qwen3.5-397B-A17B",
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
      resolvedProvider: "modelscope",
      resolvedModel: "Qwen/Qwen3.5-397B-A17B"
    });
  });

  it("returns a retryable transport failure without leaking secrets to logs", async () => {
    const logs = [];
    const result = await runModelScopeVisionInference({
      apiKey: "super-secret-token",
      model: "Qwen/Qwen3.5-397B-A17B",
      imageBuffer: sampleImage,
      logger(message) {
        logs.push(message);
      },
      fetchImpl: async () => {
        throw new Error("socket hang up");
      }
    });

    expect(result).toMatchObject({
      success: false,
      retryable: true,
      reason: "transport_error"
    });
    expect(logs.join("\n")).not.toContain("super-secret-token");
  });

  it("returns a retryable failure when the provider responds with no choices", async () => {
    const result = await runModelScopeVisionInference({
      apiKey: "secret",
      model: "Qwen/Qwen3.5-397B-A17B",
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
