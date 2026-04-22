import sharp from "sharp";

import { loadConfig } from "../../../skills/captcha-auto-skill/src/config.mjs";
import { fetchModelScopeCatalog } from "../../../skills/captcha-auto-skill/src/catalog/modelscope.mjs";
import { runModelScopeVisionInference } from "../../../skills/captcha-auto-skill/src/providers/modelscope.mjs";
import { fixturePath } from "../test-helpers.mjs";

const DEFAULT_FIXTURE = fixturePath("captcha", "simple.svg");

export async function runModelScopeProbe({
  cwd = process.cwd(),
  env = process.env,
  model = null
} = {}) {
  const config = loadConfig({
    argv: [`--input=${DEFAULT_FIXTURE}`],
    cwd,
    env
  });

  if (!config.modelscope.apiKey) {
    throw new Error(
      "Missing CAPTCHA_MODELSCOPE_API_KEY. Set it in the current shell or the project-local .env.local."
    );
  }

  const selectedModel =
    model ?? (await fetchModelScopeCatalog()).find(Boolean)?.model ?? "Qwen/Qwen3.5-397B-A17B";
  const imageBuffer = await sharp(DEFAULT_FIXTURE).png().toBuffer();

  return runModelScopeVisionInference({
    apiKey: config.modelscope.apiKey,
    baseUrl: config.modelscope.baseUrl,
    model: selectedModel,
    imageBuffer
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const modelArg = process.argv.find((arg) => arg.startsWith("--model="));
  const model = modelArg ? modelArg.slice("--model=".length) : null;
  runModelScopeProbe({ model })
    .then((result) => {
      console.log(JSON.stringify(result, null, 2));
      if (!result.success) {
        process.exitCode = 1;
      }
    })
    .catch((error) => {
      console.error(error.message);
      process.exit(1);
    });
}
