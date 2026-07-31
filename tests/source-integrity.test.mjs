import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

async function read(path) {
  return readFile(new URL(path, root), "utf8");
}

test("does not ship private user data or AI runtime dependencies", async () => {
  const [runner, launcher, page, packageJson] = await Promise.all([
    read("control_server.py"),
    read("ControlModule"),
    read("app/page.tsx"),
    read("package.json"),
  ]);
  const publicSource = `${runner}\n${launcher}\n${page}\n${packageJson}`;

  assert.doesNotMatch(publicSource, /\/Users\/[A-Za-z0-9._-]+/);
  assert.doesNotMatch(publicSource, /codex-runtimes|ChatGPTUser|oai-authenticated/i);
  assert.doesNotMatch(packageJson, /openai|chatgpt|codex/i);
  assert.match(launcher, /#token=\$\{token\}/);
  assert.doesNotMatch(launcher, /\?token=/);
  assert.match(launcher, /Resources\/runtime\/bin\/node/);
  assert.match(launcher, /node_modules\/vinext\/dist\/cli\.js/);
});

test("keeps all private runtime paths out of Git", async () => {
  const ignore = await read(".gitignore");
  for (const expected of [
    "/control-projects.json",
    "/control-projects.corrupt-*.json",
    "/control-logs/",
    "/control-module.log",
    "/control-runner.log",
    "/.control-runtime/",
    "/control-data.sqlite*",
    "/__pycache__/",
  ]) {
    assert.match(ignore, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
});

test("binds the dashboard to loopback and documents dangerous capabilities", async () => {
  const [packageJson, readme, proxy, securityHeaders] = await Promise.all([
    read("package.json"),
    read("README.md"),
    read("proxy.ts"),
    read("security-headers.ts"),
  ]);
  const parsed = JSON.parse(packageJson);

  assert.match(parsed.scripts.start, /--hostname 127\.0\.0\.1/);
  assert.match(parsed.scripts.dev, /--hostname 127\.0\.0\.1/);
  assert.equal(parsed.license, "MIT");
  assert.match(readme, /\/bin\/zsh -c/);
  assert.match(readme, /SIGKILL/);
  assert.match(readme, /does \*\*not\*\* require Codex, ChatGPT, OpenAI/i);
  assert.match(readme, /not.*SaaS/i);
  assert.match(readme, /URL fragment/);
  assert.match(proxy, /SECURITY_HEADERS/);
  assert.match(securityHeaders, /frame-ancestors 'none'/);
  assert.match(securityHeaders, /X-Frame-Options/);
  assert.match(securityHeaders, /Referrer-Policy/);
});

test("contains the public trust files and no stale starter directories", async () => {
  const files = await readdir(root);
  for (const expected of ["LICENSE", "README.md", "SECURITY.md", "CONTRIBUTING.md", "THIRD_PARTY_NOTICES.md", "BUNDLED_RUNTIME.md"]) {
    assert.ok(files.includes(expected), `${expected} should exist`);
  }
  for (const removed of ["db", "drizzle", "worker", "build", ".openai", "package-lock.json", "postcss.config.mjs"]) {
    assert.ok(!files.includes(removed), `${removed} should not be part of the public source tree`);
  }
});
