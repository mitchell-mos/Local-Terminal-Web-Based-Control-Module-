#!/usr/bin/env node

import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = resolve(dirname(scriptPath), "..");
const versionPath = resolve(projectRoot, "version.json");
const packagePath = resolve(projectRoot, "package.json");
const levels = new Set(["major", "update", "fix"]);

export function validateVersion(value) {
  if (!value || typeof value !== "object") {
    throw new TypeError("Version data must be an object.");
  }

  const version = {
    major: value.major,
    update: value.update,
    fix: value.fix,
  };
  if (!Number.isInteger(version.major) || version.major < 1) {
    throw new TypeError("The major version must be a positive integer.");
  }
  if (!Number.isInteger(version.update) || version.update < 0 || version.update > 99) {
    throw new TypeError("The update version must be an integer from 0 to 99.");
  }
  if (!Number.isInteger(version.fix) || version.fix < 0) {
    throw new TypeError("The fix version must be a non-negative integer.");
  }
  return version;
}

export function formatVersion(value) {
  const version = validateVersion(value);
  return `v${version.major}.${String(version.update).padStart(2, "0")}.${version.fix}`;
}

export function packageVersion(value) {
  const version = validateVersion(value);
  return `${version.major}.${version.update}.${version.fix}`;
}

export function bumpVersion(value, level) {
  const version = validateVersion(value);
  if (!levels.has(level)) {
    throw new TypeError("Choose one version level: major, update, or fix.");
  }
  if (level === "major") {
    return { major: version.major + 1, update: 0, fix: 0 };
  }
  if (level === "update") {
    if (version.update === 99) {
      throw new RangeError("Update 99 is the limit for this major version. Choose major instead.");
    }
    return { major: version.major, update: version.update + 1, fix: 0 };
  }
  return { ...version, fix: version.fix + 1 };
}

export function classifyTransition(previousValue, currentValue) {
  const previous = validateVersion(previousValue);
  const current = validateVersion(currentValue);
  if (current.major === previous.major + 1 && current.update === 0 && current.fix === 0) {
    return "major";
  }
  if (
    current.major === previous.major
    && current.update === previous.update + 1
    && current.fix === 0
  ) {
    return "update";
  }
  if (
    current.major === previous.major
    && current.update === previous.update
    && current.fix === previous.fix + 1
  ) {
    return "fix";
  }
  throw new Error(
    `Version must advance exactly once from ${formatVersion(previous)} as a major, update, or fix release.`,
  );
}

export function classifyPush(previousValue, currentValue) {
  validateVersion(currentValue);
  if (previousValue === null) return "baseline";
  return classifyTransition(previousValue, currentValue);
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function currentVersion() {
  const version = validateVersion(await readJson(versionPath));
  const packageMetadata = await readJson(packagePath);
  const expectedPackageVersion = packageVersion(version);
  if (packageMetadata.version !== expectedPackageVersion) {
    throw new Error(
      `package.json is ${packageMetadata.version}; expected ${expectedPackageVersion} for ${formatVersion(version)}.`,
    );
  }
  return { version, packageMetadata };
}

async function previousVersion(ref) {
  try {
    const { stdout } = await execFileAsync("git", ["show", `${ref}:version.json`], {
      cwd: projectRoot,
      encoding: "utf8",
    });
    return validateVersion(JSON.parse(stdout));
  } catch (error) {
    const detail = `${error?.stderr || ""}\n${error?.message || ""}`;
    if (/version\.json.*(?:does not exist|exists on disk|not in)|path 'version\.json'/i.test(detail)) {
      return null;
    }
    throw new Error(`Could not read the previous version from ${ref}.`);
  }
}

async function bump(level) {
  const { version, packageMetadata } = await currentVersion();
  const next = bumpVersion(version, level);
  packageMetadata.version = packageVersion(next);
  await writeFile(versionPath, `${JSON.stringify(next, null, 2)}\n`, "utf8");
  await writeFile(packagePath, `${JSON.stringify(packageMetadata, null, 2)}\n`, "utf8");
  process.stdout.write(`${formatVersion(version)} → ${formatVersion(next)} (${level})\n`);
}

async function check(ref) {
  if (!ref) throw new Error("Provide the Git ref from before this push.");
  const { version } = await currentVersion();
  const previous = await previousVersion(ref);
  const level = classifyPush(previous, version);
  if (level === "baseline") {
    process.stdout.write(`Version policy established at ${formatVersion(version)}.\n`);
    return;
  }
  process.stdout.write(`${formatVersion(previous)} → ${formatVersion(version)} (${level})\n`);
}

async function main() {
  const [command, argument] = process.argv.slice(2);
  if (command === "bump") return bump(argument);
  if (command === "check") return check(argument);
  throw new Error(
    "Usage: node support/version.mjs bump <major|update|fix> | check <previous-git-ref>",
  );
}

if (resolve(process.argv[1] || "") === scriptPath) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
