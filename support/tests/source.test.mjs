import assert from "node:assert/strict";
import { access, chmod, cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const execFileAsync = promisify(execFile);

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

test("uninstall removes only its verified source folder", { skip: process.platform !== "darwin" }, async () => {
  const temporaryRoot = await mkdtemp(join(tmpdir(), "control-module-uninstall-test-"));
  const fakeHome = join(temporaryRoot, "home");
  const source = join(temporaryRoot, "download", "Control Module Test Copy");
  const otherCopy = join(temporaryRoot, "download", "Other Control Module Copy");
  const application = join(fakeHome, "Applications", "Control Module.app");
  const shortcut = join(fakeHome, "Desktop", "Control Module.app");
  const settings = join(fakeHome, "Library", "Application Support", "Control Module", "data", "projects.json");
  const uninstallScript = join(source, "support", "mac", "uninstall.sh");

  try {
    await mkdir(join(source, "support", "mac"), { recursive: true });
    await mkdir(join(source, "server"), { recursive: true });
    await mkdir(otherCopy, { recursive: true });
    await mkdir(application, { recursive: true });
    await mkdir(shortcut, { recursive: true });
    await mkdir(join(settings, ".."), { recursive: true });
    await writeFile(join(source, "package.json"), '{"name":"control-module"}\n');
    await writeFile(join(source, "ControlModule"), "#!/bin/zsh\n");
    await writeFile(join(source, "server", "control_server.py"), "# test fixture\n");
    await chmod(join(source, "ControlModule"), 0o755);
    await cp(new URL("support/mac/uninstall.sh", root), uninstallScript);
    await chmod(uninstallScript, 0o755);
    await writeFile(join(otherCopy, "keep.txt"), "keep\n");
    await writeFile(join(application, "keep.txt"), "keep\n");
    await writeFile(join(shortcut, "keep.txt"), "keep\n");
    await writeFile(settings, "[]\n");

    await execFileAsync("/bin/zsh", [uninstallScript, "--source", source, "--remove-source"], {
      env: { ...process.env, HOME: fakeHome },
    });

    await assert.rejects(access(source));
    await assert.doesNotReject(access(join(fakeHome, ".Trash", "Control Module Test Copy", "package.json")));
    await assert.doesNotReject(access(join(otherCopy, "keep.txt")));
    await assert.doesNotReject(access(join(application, "keep.txt")));
    await assert.doesNotReject(access(join(shortcut, "keep.txt")));
    await assert.doesNotReject(access(settings));
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("ships relocatable native setup and uninstall apps", async () => {
  const [launcher, nativeLauncher, installer, uninstaller, builder, setupBuilder, setupSource, setupStore, removeBuilder, uninstallSource, iconBuilder, trashIcon, plist, readme] = await Promise.all([
    read("ControlModule"),
    read("support/mac/Launch.applescript"),
    read("support/mac/install.sh"),
    read("support/mac/uninstall.sh"),
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
  assert.match(launcher, /uname -m/);
  assert.match(launcher, /Rosetta translation are not supported/);
  assert.doesNotMatch(launcher, /Desktop\/control module/);
  assert.match(nativeLauncher, /Contents\/Resources\/ControlModule/);
  assert.match(nativeLauncher, /\/bin\/zsh/);
  assert.match(installer, /project-path/);
  assert.match(installer, /install-path/);
  assert.match(installer, /--web-port/);
  assert.match(installer, /web-port/);
  assert.match(installer, /chmod 600/);
  assert.match(installer, /nodejs\.org\/download\/release/);
  assert.match(installer, /NODE_SHA256/);
  assert.match(installer, /shasum -a 256/);
  assert.match(installer, /runtime_is_valid/);
  assert.match(uninstaller, /--dry-run/);
  assert.match(uninstaller, /--stop-only/);
  assert.match(uninstaller, /Other Control Module folders, apps, shortcuts, browser data, and settings: keep/);
  assert.match(uninstaller, /process_uses_source/);
  assert.doesNotMatch(uninstaller, /clear_browser_data/);
  assert.doesNotMatch(uninstaller, /APP_TARGETS|TOOL_TARGETS/);
  assert.doesNotMatch(uninstaller, /rm -rf/);
  assert.match(uninstaller, /\.Trash/);
  assert.match(uninstaller, /Refusing to operate/);
  assert.match(builder, /ControlModule\.icns/);
  assert.match(builder, /Launch\.applescript/);
  assert.match(builder, /lipo.*-thin arm64/);
  assert.match(builder, /ditto "\$RUNTIME_DIR"/);
  assert.match(builder, /codesign --force --deep --sign - "\$STAGING_APP"/);
  assert.match(setupBuilder, /osacompile/);
  assert.match(setupBuilder, /Setup\.app/);
  assert.match(setupBuilder, /lipo.*-thin arm64/);
  assert.match(setupBuilder, /LSRequiresNativeExecution/);
  assert.match(setupSource, /Dashboard port/);
  assert.match(setupSource, /--web-port/);
  assert.match(setupSource, /support\/mac\/store\.sh/);
  assert.match(setupSource, /Control Module folder/);
  assert.doesNotMatch(setupSource, /installLocation is "Desktop"/);
  assert.match(setupSource, /Desktop shortcut/);
  assert.doesNotMatch(setupSource, /Control Module and Setup shortcuts/);
  assert.match(setupSource, /stay in the Control Module folder/);
  assert.match(setupSource, /no AI service, account, analytics, or cloud connection/i);
  assert.doesNotMatch(setupSource, /choose folder/i);
  assert.match(setupSource, /parentFolder/);
  assert.match(setupSource, /\/bin\/test/);
  assert.doesNotMatch(setupSource, /\/usr\/bin\/test/);
  assert.match(setupStore, /SOURCE_DIR\/Setup\.app/);
  assert.match(setupStore, /Desktop\/Setup\.app/);
  assert.doesNotMatch(setupStore, /ln -s/);
  assert.match(setupStore, /io\.github\.mitchell-mos\.control-module\.setup/);
  assert.match(setupStore, /bundle_is_setup/);
  assert.match(removeBuilder, /Uninstall\.app/);
  assert.match(removeBuilder, /Trash\.icns/);
  assert.match(removeBuilder, /lipo.*-thin arm64/);
  assert.match(removeBuilder, /LSRequiresNativeExecution/);
  assert.match(uninstallSource, /No, I don’t want to/);
  assert.match(uninstallSource, /Yes, I’d like to/);
  assert.match(uninstallSource, /--remove-source/);
  assert.doesNotMatch(uninstallSource, /Type UNINSTALL/);
  assert.doesNotMatch(uninstallSource, /choose from list/);
  assert.match(uninstallSource, /on run[\s\S]*set confirmDialog[\s\S]*set sourceFolder/);
  assert.match(uninstallSource, /support\/mac\/uninstall\.sh/);
  assert.doesNotMatch(uninstallSource, /choose folder/i);
  assert.doesNotMatch(uninstallSource, /savedSourceFolder/);
  assert.match(uninstallSource, /Only the folder containing this Uninstall app is moved to Trash/);
  assert.match(uninstallSource, /parentFolder/);
  assert.match(uninstallSource, /\/bin\/test/);
  assert.doesNotMatch(uninstallSource, /\/usr\/bin\/test/);
  assert.match(trashIcon, /<svg/);
  assert.match(trashIcon, /#c73535/);
  assert.match(iconBuilder, /public\/gear\.svg/);
  assert.match(plist, /CFBundleIconFile/);
  assert.match(plist, /NSDesktopFolderUsageDescription/);
  assert.match(plist, /LSRequiresNativeExecution/);
  assert.match(plist, /arm64/);
  assert.doesNotMatch(plist, /codex/i);
  assert.match(readme, /Desktop shortcut/);
  assert.match(readme, /Setup\.app/);
  assert.match(readme, /Uninstall\.app/);
  assert.match(readme, /signed and notarized/i);
  assert.match(readme, /directly from nodejs\.org/i);
});
