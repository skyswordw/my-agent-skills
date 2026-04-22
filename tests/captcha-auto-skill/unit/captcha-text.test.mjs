import { describe, expect, it } from "vitest";

import { interpretCaptchaText } from "../../../skills/captcha-auto-skill/src/captcha/text.mjs";

describe("interpretCaptchaText", () => {
  it("keeps normal alphanumeric captchas as uppercase text", () => {
    expect(interpretCaptchaText(" aB-12 ")).toEqual({
      text: "AB12",
      kind: "text",
      normalizedInput: "AB12"
    });
  });

  it("solves arithmetic captchas ending with an equals sign", () => {
    expect(interpretCaptchaText("15+5=")).toEqual({
      text: "20",
      kind: "arithmetic",
      normalizedInput: "15+5="
    });
  });

  it("solves arithmetic captchas with spaces and x multiplication", () => {
    expect(interpretCaptchaText(" 8 x 7 = ")).toEqual({
      text: "56",
      kind: "arithmetic",
      normalizedInput: "8X7="
    });
  });

  it("returns empty text when nothing useful remains", () => {
    expect(interpretCaptchaText(" -- \n")).toEqual({
      text: "",
      kind: "text",
      normalizedInput: ""
    });
  });
});
