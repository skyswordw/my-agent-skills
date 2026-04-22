import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";
import { installSkillBundle, listSkillBundleFiles, skillRoot } from "../test-helpers.mjs";

const tempDirs = [];
const tempFiles = [];

function makeTempDir() {
  const dir = mkdtempSync(path.join(os.tmpdir(), "captcha-auto-install-"));
  tempDirs.push(dir);
  return dir;
}

afterEach(() => {
  while (tempDirs.length) {
    rmSync(tempDirs.pop(), { recursive: true, force: true });
  }
  while (tempFiles.length) {
    rmSync(tempFiles.pop(), { recursive: true, force: true });
  }
});

describe("skill packaging", () => {
  it("ships the required skill bundle files", () => {
    const bundleFiles = listSkillBundleFiles();

    expect(existsSync(path.join(skillRoot, "SKILL.md"))).toBe(true);
    expect(existsSync(path.join(skillRoot, "agents", "openai.yaml"))).toBe(true);
    expect(existsSync(path.join(skillRoot, "scripts", "run.mjs"))).toBe(true);
    expect(existsSync(path.join(skillRoot, "package.json"))).toBe(true);
    expect(existsSync(path.join(skillRoot, ".env.example"))).toBe(true);
    expect(existsSync(path.join(skillRoot, "src", "browser", "run-captcha-flow.mjs"))).toBe(true);
    expect(existsSync(path.join(skillRoot, "src", "run-captcha.mjs"))).toBe(true);
    expect(bundleFiles).toContain("SKILL.md");
    expect(bundleFiles).toContain("agents/openai.yaml");
    expect(bundleFiles.some((file) => file.startsWith("node_modules/"))).toBe(false);
    expect(bundleFiles).not.toContain("eng.traineddata");
  });

  it("copies the self-contained skill bundle into a target project install path", () => {
    const targetProject = makeTempDir();

    installSkillBundle(targetProject);

    expect(
      existsSync(path.join(targetProject, ".codex/skills/captcha-auto-skill/SKILL.md"))
    ).toBe(true);
    expect(
      existsSync(path.join(targetProject, ".codex/skills/captcha-auto-skill/agents/openai.yaml"))
    ).toBe(true);
    expect(
      existsSync(path.join(targetProject, ".codex/skills/captcha-auto-skill/scripts/run.mjs"))
    ).toBe(true);
    expect(
      existsSync(path.join(targetProject, ".codex/skills/captcha-auto-skill/package.json"))
    ).toBe(true);
    expect(
      existsSync(path.join(targetProject, ".codex/skills/captcha-auto-skill/.env.example"))
    ).toBe(true);
    expect(
      existsSync(
        path.join(targetProject, ".codex/skills/captcha-auto-skill/src/browser/run-captcha-flow.mjs")
      )
    ).toBe(true);
  });

  it("keeps the installed run script self-contained and sanitized", () => {
    const targetProject = makeTempDir();

    installSkillBundle(targetProject);

    const installedRunScript = readFileSync(
      path.join(targetProject, ".codex/skills/captcha-auto-skill/scripts/run.mjs"),
      "utf8"
    );
    const publishedDocs = readFileSync(path.join(skillRoot, "SKILL.md"), "utf8");
    const agentPrompt = readFileSync(path.join(skillRoot, "agents", "openai.yaml"), "utf8");

    expect(installedRunScript).not.toContain("../../../src/");
    expect(installedRunScript).not.toMatch(/\/Volumes\/DataHouse|\/Users\/skywalker/);
    expect(publishedDocs).not.toMatch(/\/Volumes\/DataHouse|\/Users\/skywalker/);
    expect(publishedDocs).not.toContain("MSI");
    expect(publishedDocs).toMatch(/candidate answer/i);
    expect(publishedDocs).toMatch(/local OCR/i);
    expect(agentPrompt).not.toContain("submit");
  });

  it("does not copy local install artifacts into the installed bundle", () => {
    const targetProject = makeTempDir();
    const leakFile = path.join(skillRoot, "node_modules", ".captcha-test-leak.txt");
    const ocrArtifact = path.join(skillRoot, "eng.traineddata");
    tempFiles.push(leakFile, ocrArtifact);

    writeFileSync(leakFile, "leak", "utf8");
    writeFileSync(ocrArtifact, "generated-runtime-artifact", "utf8");

    installSkillBundle(targetProject);

    expect(
      existsSync(path.join(targetProject, ".codex/skills/captcha-auto-skill/node_modules"))
    ).toBe(false);
    expect(
      existsSync(
        path.join(targetProject, ".codex/skills/captcha-auto-skill/node_modules/.captcha-test-leak.txt")
      )
    ).toBe(false);
    expect(
      existsSync(path.join(targetProject, ".codex/skills/captcha-auto-skill/eng.traineddata"))
    ).toBe(false);
  });
});
