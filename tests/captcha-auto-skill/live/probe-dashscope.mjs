import sharp from "sharp";

import { loadConfig } from "../../../skills/captcha-auto-skill/src/config.mjs";
import { DASHSCOPE_DEFAULT_MODEL } from "../../../skills/captcha-auto-skill/src/model-preferences.mjs";
import { runDashScopeVisionInference } from "../../../skills/captcha-auto-skill/src/providers/dashscope.mjs";
import { fixturePath } from "../test-helpers.mjs";

const DEFAULT_FIXTURE = fixturePath("captcha", "simple.svg");

export async function runDashScopeProbe({
  cwd = process.cwd(),
  env = process.env,
  model = DASHSCOPE_DEFAULT_MODEL
} = {}) {
  const config = loadConfig({
    argv: [`--input=${DEFAULT_FIXTURE}`],
    cwd,
    env
  });

  if (!config.dashscope.apiKey) {
    throw new Error(
      "Missing CAPTCHA_DASHSCOPE_API_KEY. Set it in the current shell or the project-local .env.local."
    );
  }

  const imageBuffer = await sharp(DEFAULT_FIXTURE).png().toBuffer();
  return runDashScopeVisionInference({
    apiKey: config.dashscope.apiKey,
    baseUrl: config.dashscope.baseUrl,
    model,
    imageBuffer
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const modelArg = process.argv.find((arg) => arg.startsWith("--model="));
  const model = modelArg ? modelArg.slice("--model=".length) : DASHSCOPE_DEFAULT_MODEL;
  runDashScopeProbe({ model })
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
