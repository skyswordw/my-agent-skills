import { cpSync, mkdirSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const testsRoot = path.dirname(fileURLToPath(import.meta.url));
const ignoredNames = new Set(["node_modules", "eng.traineddata"]);

export const repoRoot = path.resolve(testsRoot, "../..");
export const skillRoot = path.join(repoRoot, "skills", "captcha-auto-skill");
export const fixturesRoot = path.join(testsRoot, "fixtures");

export function fixturePath(...segments) {
  return path.join(fixturesRoot, ...segments);
}

export function listSkillBundleFiles(root = skillRoot) {
  const files = [];
  walk(root, "");
  return files.sort();

  function walk(currentPath, relativePath) {
    const entryName = path.basename(currentPath);
    if (relativePath && ignoredNames.has(entryName)) {
      return;
    }

    const stats = statSync(currentPath);
    if (stats.isDirectory()) {
      for (const child of readdirSync(currentPath)) {
        walk(path.join(currentPath, child), path.join(relativePath, child));
      }
      return;
    }

    files.push(relativePath);
  }
}

export function installSkillBundle(targetProject) {
  mkdirSync(path.join(targetProject, ".codex", "skills"), { recursive: true });
  cpSync(skillRoot, path.join(targetProject, ".codex", "skills", "captcha-auto-skill"), {
    recursive: true,
    filter: (sourcePath) => !ignoredNames.has(path.basename(sourcePath))
  });
}
