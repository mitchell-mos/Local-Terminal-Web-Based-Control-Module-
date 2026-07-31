import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import test from "node:test";

const root = new URL("../../", import.meta.url);

async function read(path) {
  return readFile(new URL(path, root), "utf8");
}

test("does not ship private user data or AI runtime dependencies", async () => {
  const [runner, launcher, page, packageJson] = await Promise.all([
    read("server/control_server.py"),
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
    "/.control-module-data/",
    "/control-data.sqlite*",
    "__pycache__/",
  ]) {
    assert.match(ignore, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
});

test("binds the dashboard to loopback and documents dangerous capabilities", async () => {
  const [packageJson, readme, proxy, securityHeaders] = await Promise.all([
    read("package.json"),
    read("README.md"),
    read("proxy.ts"),
    read("lib/security-headers.ts"),
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
  for (const expected of ["LICENSE", "README.md", "Setup.app", "Uninstall.app", ".github", "support", "server", "lib"]) {
    assert.ok(files.includes(expected), `${expected} should exist`);
  }
  for (const removed of ["Control Module Setup.app", "Install Control Module.command", "Uninstall Control Module.command", "docs", "packaging", "scripts", "tests", "db", "drizzle", "worker", "build", ".openai", "package-lock.json", "postcss.config.mjs"]) {
    assert.ok(!files.includes(removed), `${removed} should not be part of the public source tree`);
  }

  const docs = await readdir(new URL("support/docs/", root));
  for (const expected of ["Runtime.md", "Notices.md"]) {
    assert.ok(docs.includes(expected), `support/docs/${expected} should exist`);
  }
  await assert.doesNotReject(access(new URL(".github/SECURITY.md", root)));
  await assert.doesNotReject(access(new URL(".github/CONTRIBUTING.md", root)));
});

test("keeps local documentation links routed to existing files", async () => {
  const markdown = await read("README.md");
  const localLinks = [...markdown.matchAll(/\]\((?!https?:|#)([^)#]+)(?:#[^)]*)?\)/g)].map(
    (match) => match[1],
  );

  assert.ok(localLinks.length > 0);
  for (const link of localLinks) {
    await assert.doesNotReject(access(new URL(link, root)), `${link} should resolve`);
  }
});

test("ships relocatable native setup and uninstall apps", async () => {
  const [launcher, installer, uninstaller, browserCleanup, builder, setupBuilder, setupSource, setupStore, removeBuilder, uninstallSource, iconBuilder, trashIcon, plist, readme] = await Promise.all([
    read("ControlModule"),
    read("support/mac/install.sh"),
    read("support/mac/uninstall.sh"),
    read("support/mac/clear.py"),
    read("support/mac/app.sh"),
    read("support/mac/setup.sh"),
    read("support/mac/Setup.applescript"),
    read("support/mac/store.sh"),
    read("support/mac/remove.sh"),
    read("support/mac/Uninstall.applescript"),
    read("support/mac/icon.sh"),
    read("support/mac/Trash.svg"),
    read("support/mac/App.plist"),
    read("README.md"),
  ]);

  assert.match(launcher, /Library\/Application Support\/Control Module/);
  assert.match(launcher, /server\/control_server\.py/);
  assert.match(launcher, /Resources\/control-module/);
  assert.match(launcher, /CONTROL_MODULE_WEB_PORT/);
  assert.doesNotMatch(launcher, /Desktop\/control module/);
  assert.match(installer, /project-path/);
  assert.match(installer, /install-path/);
  assert.match(installer, /--web-port/);
  assert.match(installer, /web-port/);
  assert.match(installer, /chmod 600/);
  assert.match(uninstaller, /api\/projects\/stop-all/);
  assert.match(uninstaller, /--dry-run/);
  assert.match(uninstaller, /--stop-only/);
  assert.match(uninstaller, /clear_browser_data/);
  assert.match(browserCleanup, /Clear-Site-Data/);
  assert.match(browserCleanup, /localStorage\.clear/);
  assert.match(uninstaller, /is_control_module_app/);
  assert.match(uninstaller, /is_control_module_tool/);
  assert.match(uninstaller, /Desktop\/Setup\.app/);
  assert.match(uninstaller, /\.Trash/);
  assert.match(uninstaller, /Refusing to remove/);
  assert.match(builder, /ControlModule\.icns/);
  assert.match(builder, /codesign --force --deep --sign - "\$OUTPUT_APP"/);
  assert.match(setupBuilder, /osacompile/);
  assert.match(setupBuilder, /Setup\.app/);
  assert.match(setupSource, /Dashboard port/);
  assert.match(setupSource, /--web-port/);
  assert.match(setupSource, /support\/mac\/store\.sh/);
  assert.match(setupSource, /move into the support folder/);
  assert.match(setupSource, /no AI service, account, analytics, or cloud connection/i);
  assert.match(setupStore, /support\/Setup\.app/);
  assert.match(setupStore, /io\.github\.mitchell-mos\.control-module\.setup/);
  assert.match(setupStore, /bundle_is_setup/);
  assert.match(removeBuilder, /Uninstall\.app/);
  assert.match(removeBuilder, /Trash\.icns/);
  assert.match(uninstallSource, /Type UNINSTALL/);
  assert.match(uninstallSource, /support\/mac\/uninstall\.sh/);
  assert.match(trashIcon, /<svg/);
  assert.match(trashIcon, /#c73535/);
  assert.match(iconBuilder, /public\/gear\.svg/);
  assert.match(plist, /CFBundleIconFile/);
  assert.match(plist, /NSDesktopFolderUsageDescription/);
  assert.doesNotMatch(plist, /codex/i);
  assert.match(readme, /Desktop shortcut/);
  assert.match(readme, /Setup\.app/);
  assert.match(readme, /Uninstall\.app/);
  assert.match(readme, /signed and notarized/i);
});
