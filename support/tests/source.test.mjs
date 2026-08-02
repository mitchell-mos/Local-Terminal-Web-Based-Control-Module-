import assert from "node:assert/strict";
import { access, chmod, cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { runInNewContext } from "node:vm";
import test from "node:test";

const root = new URL("../../", import.meta.url);
const execFileAsync = promisify(execFile);

async function read(path) {
  return readFile(new URL(path, root), "utf8");
}

test("does not ship private user data or unrelated runtime state", async () => {
  const [runner, launcher, page, packageJson, proxy, restartIcon, browserTabs] = await Promise.all([
    read("server/control_server.py"),
    read("ControlModule"),
    read("app/page.tsx"),
    read("package.json"),
    read("proxy.ts"),
    read("public/icons/restart-loader.svg"),
    read("server/browser_tabs.jxa"),
  ]);
  const publicSource = `${runner}\n${launcher}\n${page}\n${packageJson}\n${proxy}\n${browserTabs}`;

  assert.doesNotMatch(publicSource, /\/Users\/[A-Za-z0-9._-]+/);
  assert.match(launcher, /local url="\$\{WEB_URL\}"/);
  assert.doesNotMatch(launcher, /[?#&](?:token|instance|runner)=/);
  assert.doesNotMatch(launcher, /--authorize-url|control-module-\$INSTANCE_ID:\/\/authorize/);
  assert.match(launcher, /Resources\/runtime\/bin\/node/);
  assert.match(launcher, /node_modules\/vinext\/dist\/cli\.js/);
  assert.match(launcher, /CONTROL_MODULE_SOURCE_DIR/);
  assert.match(launcher, /CONTROL_MODULE_CONFIG_DIR/);
  assert.match(runner, /verified_native_app_path/);
  assert.match(runner, /\/api\/system\/open-settings/);
  assert.match(runner, /\/api\/system\/open-uninstall/);
  assert.match(runner, /\/api\/projects\/inspect/);
  assert.match(runner, /\/api\/system\/choose-folder/);
  assert.match(runner, /MAX_PACKAGE_JSON_BYTES/);
  assert.match(runner, /PROJECT_FOLDER_ROOT/);
  assert.match(runner, /resolved_path\.startswith\(safe_prefix\)/);
  assert.match(runner, /send_allowed_origin_header/);
  assert.doesNotMatch(runner, /send_header\("Access-Control-Allow-Origin", origin\)/);
  assert.match(runner, /BROWSER_BLOCKED_PROJECT_PORTS/);
  assert.match(runner, /project_port_restriction_reason/);
  assert.match(runner, /\/usr\/bin\/open/);
  assert.doesNotMatch(runner, /shell=True/);
  assert.match(page, /Open app settings/);
  assert.match(page, /Uninstall this copy/);
  assert.doesNotMatch(page, /Authorize this browser|X-Control-Token|session-token/);
  assert.match(page, /fetch\(path/);
  assert.match(page, /Basic/);
  assert.match(page, /Advanced/);
  assert.match(page, /Edit in Advanced/);
  assert.match(page, /App functions/);
  assert.match(page, /Process commands/);
  assert.match(page, /Detect again/);
  assert.match(page, /PROJECT_TRANSFER_FORMAT/);
  assert.match(page, /control-module-projects/);
  assert.match(page, /Import projects/);
  assert.match(page, /Nothing was started/);
  assert.match(page, /Keep the file private/);
  assert.match(runner, /detect_package_manager/);
  assert.match(runner, /run_project_hook/);
  assert.match(page, /BLOCKED_PORT_ROWS/);
  assert.match(page, /Blocked ports/);
  assert.match(page, /6665–6669/);
  assert.match(page, /searchParams\.delete\("instance"\)/);
  assert.match(page, /searchParams\.delete\("runner"\)/);
  assert.match(page, /sessionStorage\.removeItem\("control-module-runner-token"\)/);
  assert.match(page, /sessionStorage\.removeItem\("control-module-instance-id"\)/);
  assert.doesNotMatch(page, /searchParams\.set\("instance"/);
  assert.doesNotMatch(page, /searchParams\.set\("runner"/);
  assert.match(page, /\/api\/projects\/reorder/);
  assert.match(page, /draggable=\{canReorderProjects\}/);
  assert.match(page, /Dismiss \$\{project\.name\} error/);
  assert.match(page, /control-module-project-filters-v1/);
  assert.match(page, /window\.localStorage\.setItem\(PROJECT_FILTERS_KEY/);
  assert.match(page, /Published site/);
  assert.match(page, /projectDropTargetRef/);
  assert.match(page, /setDragImage/);
  assert.match(page, /beginProjectRateLimitedAction\(project\.id\)/);
  assert.match(page, /projectCooldownIds/);
  assert.match(page, /busyProjectIds/);
  assert.match(page, /projectWindowName\(project\.id\)/);
  assert.match(page, /tabWasOpen/);
  assert.match(page, /tabReloaded/);
  assert.match(page, /_control_reload/);
  assert.match(page, /Go to refreshed tab/);
  assert.match(page, /Go to browser/);
  assert.match(page, /Open website/);
  assert.doesNotMatch(page, />\s*Deny\s*</);
  assert.doesNotMatch(page, />\s*Accept\s*</);
  assert.match(restartIcon, /M9\.825 20\.7q-2\.575/);
  assert.doesNotMatch(restartIcon, /transform=|stroke-width=/);
  assert.match(runner, /\/api\/projects\/browser-tabs/);
  assert.match(runner, /project_browser_tabs/);
  assert.match(browserTabs, /http:\/\/127\.0\.0\.1:/);
  assert.match(browserTabs, /http:\/\/localhost:/);
  assert.match(browserTabs, /tab\.url\(\)/);
  assert.match(browserTabs, /freshProjectUrl\(tabUrl\)/);
  assert.match(browserTabs, /browserWindow\.currentTab = tab/);
  assert.match(browserTabs, /browserWindow\.activeTabIndex = tabIndex \+ 1/);
  assert.match(proxy, /runtime", "session-token/);
  assert.match(proxy, /"X-Control-Token": token/);
  assert.match(proxy, /sec-fetch-site/);
  assert.match(proxy, /MAX_REQUEST_BODY_BYTES/);
  assert.match(proxy, /request\.body\.getReader\(\)/);
  assert.match(proxy, /Cross-site dashboard requests are not allowed/);
  assert.doesNotMatch(proxy, /instanceId|authorizationScheme/);
});

test("matches local browser tabs by port while preserving nested routes", async () => {
  const source = await read("server/browser_tabs.jxa");
  const context = { Date: { now: () => 123456 } };
  runInNewContext(source, context);

  assert.equal(context.isMatchingProjectUrl("http://localhost:4321/", 4321), true);
  assert.equal(context.isMatchingProjectUrl("http://127.0.0.1:4321/about/team#staff", 4321), true);
  assert.equal(context.isMatchingProjectUrl("https://localhost:4321/settings?tab=local", 4321), true);
  assert.equal(context.isMatchingProjectUrl("http://localhost:43210/about", 4321), false);
  assert.equal(context.isMatchingProjectUrl("https://example.com/?port=4321", 4321), false);
  assert.equal(
    context.freshProjectUrl("http://127.0.0.1:4321/about?tab=team#staff"),
    "http://127.0.0.1:4321/about?tab=team&_control_reload=123456#staff",
  );
});

test("publishes a consistent user-facing release version", async () => {
  const [versionJson, versionSource, page, readme, packageJson, versionWorkflow] = await Promise.all([
    read("version.json"),
    read("lib/version.ts"),
    read("app/page.tsx"),
    read("README.md"),
    read("package.json"),
    read(".github/workflows/version.yml"),
  ]);
  const release = JSON.parse(versionJson);
  const label = `v${release.major}.${String(release.update).padStart(2, "0")}.${release.fix}`;
  const packageMetadata = JSON.parse(packageJson);
  const {
    bumpVersion,
    classifyPush,
    classifyTransition,
    formatVersion,
    packageVersion,
  } = await import(new URL("../version.mjs", import.meta.url));

  const baseline = { major: 1, update: 0, fix: 0 };
  assert.match(label, /^v[1-9]\d*\.\d{2}\.\d+$/);
  assert.equal(formatVersion(release), label);
  assert.equal(packageMetadata.version, packageVersion(release));
  assert.deepEqual(bumpVersion(baseline, "fix"), { major: 1, update: 0, fix: 1 });
  assert.deepEqual(bumpVersion(baseline, "update"), { major: 1, update: 1, fix: 0 });
  assert.deepEqual(bumpVersion(baseline, "major"), { major: 2, update: 0, fix: 0 });
  assert.equal(classifyPush(null, release), "baseline");
  assert.equal(classifyTransition(release, bumpVersion(release, "fix")), "fix");
  assert.equal(classifyTransition(release, bumpVersion(release, "update")), "update");
  assert.equal(classifyTransition(release, bumpVersion(release, "major")), "major");
  assert.throws(() => classifyTransition(release, release), /must advance exactly once/);
  assert.match(versionSource, /APP_VERSION_LABEL/);
  assert.match(page, /Control Module <code>\{APP_VERSION_LABEL\}<\/code>/);
  assert.match(page, /Report a bug/);
  assert.match(readme, /vMAJOR\.UPDATE\.FIX/);
  assert.match(versionWorkflow, /on:\s*\n\s*pull_request:/);
  assert.doesNotMatch(versionWorkflow, /on:\s*\n\s*push:/);
  assert.match(versionWorkflow, /pull_request\.user\.login == 'dependabot\[bot\]'/);
  assert.match(versionWorkflow, /support\/version\.mjs check/);
});

test("keeps private runtime and local development artifacts out of Git", async () => {
  const ignore = await read(".gitignore");
  for (const expected of [
    "/control-projects.json",
    "/control-projects.corrupt-*.json",
    "/control-logs/",
    "/control-module.log",
    "/control-runner.log",
    "/.control-runtime/",
    "/.control-module-data/",
    "/.control-module-instance",
    "/control-data.sqlite*",
    "/DESIGN.md",
    "/PRODUCT.md",
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
  assert.match(readme, /does not include analytics, telemetry/i);
  assert.match(readme, /not.*SaaS/i);
  assert.match(readme, /server side/i);
  assert.match(proxy, /securityHeadersForRunner/);
  assert.match(proxy, /CONTROL_MODULE_RUNNER_PORT/);
  assert.match(proxy, /CONTROL_MODULE_DATA_DIR/);
  assert.match(securityHeaders, /frame-ancestors 'none'/);
  assert.match(securityHeaders, /securityHeadersForRunner/);
  assert.match(securityHeaders, /X-Frame-Options/);
  assert.match(securityHeaders, /Referrer-Policy/);
});

test("contains the public trust files and no stale starter directories", async () => {
  const files = await readdir(root);
  for (const expected of ["CHANGELOG.md", "LICENSE", "README.md", "Setup.app", "Uninstall.app", ".github", "support", "server", "lib"]) {
    assert.ok(files.includes(expected), `${expected} should exist`);
  }
  for (const removed of ["Control Module Setup.app", "Install Control Module.command", "Uninstall Control Module.command", "docs", "packaging", "scripts", "tests", "db", "drizzle", "worker", "build", "package-lock.json", "postcss.config.mjs"]) {
    assert.ok(!files.includes(removed), `${removed} should not be part of the public source tree`);
  }

  const docs = await readdir(new URL("support/docs/", root));
  for (const expected of ["Architecture.md", "Security.md", "Troubleshooting.md", "Runtime.md", "Notices.md"]) {
    assert.ok(docs.includes(expected), `support/docs/${expected} should exist`);
  }
  await assert.doesNotReject(access(new URL(".github/SECURITY.md", root)));
  await assert.doesNotReject(access(new URL(".github/CONTRIBUTING.md", root)));
});

test("ships keyboard-complete reusable controls", async () => {
  const [components, page, styles] = await Promise.all([
    read("app/control-components.tsx"),
    read("app/page.tsx"),
    read("app/globals.css"),
  ]);

  assert.match(components, /tabIndex=\{active === kind \? 0 : -1\}/);
  assert.match(components, /ArrowRight/);
  assert.match(components, /ArrowLeft/);
  assert.match(components, /aria-atomic="true"/);
  assert.doesNotMatch(components, /aria-live=/);
  assert.match(page, /handleMenuKeyDown/);
  assert.match(page, /role="tooltip"/);
  assert.match(page, /aria-labelledby=\{`process-command-tab-/);
  assert.doesNotMatch(page, /fetch\(baseUrl/);
  assert.match(styles, /forced-colors: active/);
  assert.match(styles, /content-visibility: auto/);
});

test("pins reproducible builds and emits a compact standalone runtime", async () => {
  const [packageJson, nextConfig, launcher, installer, releaseBuilder] = await Promise.all([
    read("package.json"),
    read("next.config.ts"),
    read("ControlModule"),
    read("support/mac/install.sh"),
    read("support/mac/release.sh"),
  ]);
  const parsed = JSON.parse(packageJson);

  assert.match(parsed.packageManager, /^pnpm@11\.9\.0\+sha512\./);
  assert.match(nextConfig, /output: "standalone"/);
  assert.match(launcher, /dist\/standalone\/server\.js/);
  assert.match(installer, /SOURCE_DIR\/dist\/standalone/);
  assert.doesNotMatch(installer, /ditto "\$SOURCE_DIR\/node_modules"/);
  assert.match(installer, /prune_runtime/);
  assert.match(releaseBuilder, /git archive --format=tar HEAD/);
  assert.match(releaseBuilder, /codesign --verify --deep --strict/);
  assert.match(releaseBuilder, /shasum -a 256/);
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
  const instanceId = "12345678-1234-4123-8123-123456789abc";
  const instanceSettings = join(fakeHome, "Library", "Application Support", "Control Module", "instances", instanceId);
  const settings = join(instanceSettings, "data", "projects.json");
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
    await writeFile(join(source, ".control-module-instance"), `${instanceId}\n`);
    await chmod(join(source, "ControlModule"), 0o755);
    await cp(new URL("support/mac/uninstall.sh", root), uninstallScript);
    await chmod(uninstallScript, 0o755);
    await writeFile(join(otherCopy, "keep.txt"), "keep\n");
    await writeFile(join(application, "keep.txt"), "keep\n");
    await writeFile(join(shortcut, "keep.txt"), "keep\n");
    await writeFile(settings, "[]\n");
    await writeFile(join(instanceSettings, "instance-id"), `${instanceId}\n`);
    await writeFile(join(instanceSettings, "project-path"), `${source}\n`);
    await writeFile(join(instanceSettings, "web-port"), "18425\n");
    await writeFile(join(instanceSettings, "runner-port"), "10425\n");

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

test("uninstall distinguishes a Finder copy with a duplicated instance marker", { skip: process.platform !== "darwin" }, async () => {
  const temporaryRoot = await mkdtemp(join(tmpdir(), "control-module-duplicate-uninstall-test-"));
  const fakeHome = join(temporaryRoot, "home");
  const original = join(temporaryRoot, "download", "Original Control Module");
  const duplicate = join(temporaryRoot, "download", "Copied Control Module");
  const instanceId = "87654321-4321-4321-8321-cba987654321";
  const instanceSettings = join(fakeHome, "Library", "Application Support", "Control Module", "instances", instanceId);
  const duplicateUninstaller = join(duplicate, "support", "mac", "uninstall.sh");

  try {
    for (const source of [original, duplicate]) {
      await mkdir(join(source, "support", "mac"), { recursive: true });
      await mkdir(join(source, "server"), { recursive: true });
      await writeFile(join(source, "package.json"), '{"name":"control-module"}\n');
      await writeFile(join(source, "ControlModule"), "#!/bin/zsh\n");
      await writeFile(join(source, "server", "control_server.py"), "# test fixture\n");
      await writeFile(join(source, ".control-module-instance"), `${instanceId}\n`);
      await chmod(join(source, "ControlModule"), 0o755);
    }
    await cp(new URL("support/mac/uninstall.sh", root), duplicateUninstaller);
    await chmod(duplicateUninstaller, 0o755);
    await mkdir(instanceSettings, { recursive: true });
    await writeFile(join(instanceSettings, "instance-id"), `${instanceId}\n`);
    await writeFile(join(instanceSettings, "project-path"), `${original}\n`);
    await writeFile(join(instanceSettings, "web-port"), "19425\n");
    await writeFile(join(instanceSettings, "runner-port"), "11425\n");

    await execFileAsync("/bin/zsh", [duplicateUninstaller, "--source", duplicate, "--remove-source"], {
      env: { ...process.env, HOME: fakeHome },
    });

    await assert.rejects(access(duplicate));
    await assert.doesNotReject(access(join(fakeHome, ".Trash", "Copied Control Module", "package.json")));
    await assert.doesNotReject(access(join(original, "package.json")));
    assert.equal(await readFile(join(instanceSettings, "project-path"), "utf8"), `${original}\n`);
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
  assert.match(launcher, /CONTROL_MODULE_RUNNER_PORT/);
  assert.match(launcher, /\.control-module-instance/);
  assert.match(launcher, /instances\/\$INSTANCE_ID/);
  assert.match(launcher, /web_assets_ready/);
  assert.match(launcher, /stop_broken_owned_dashboard/);
  assert.match(launcher, /select_available_runner_port/);
  assert.match(launcher, /save_runner_port/);
  assert.match(launcher, /stop_broken_owned_runner/);
  assert.match(launcher, /RUNNER_PORT_CHANGED/);
  assert.match(launcher, /selected dashboard port \$WEB_PORT/);
  assert.doesNotMatch(launcher, /private runner port \$RUNNER_PORT is already being used/);
  assert.match(launcher, /\/assets\/index-/);
  assert.match(launcher, /uname -m/);
  assert.match(launcher, /Rosetta translation are not supported/);
  assert.doesNotMatch(launcher, /Desktop\/control module/);
  assert.match(nativeLauncher, /Contents\/Resources\/ControlModule/);
  assert.match(nativeLauncher, /\/bin\/zsh/);
  assert.doesNotMatch(nativeLauncher, /on open location|--authorize-url/);
  assert.match(installer, /project-path/);
  assert.match(installer, /install-path/);
  assert.match(installer, /runtime-path/);
  assert.match(installer, /desktop-access/);
  assert.match(installer, /prepare_private_workspace/);
  assert.match(installer, /private workspace is replaced atomically/i);
  assert.ok(
    installer.indexOf('if web_port_is_reserved_by_other_instance "$WEB_PORT"; then')
      < installer.indexOf('"$SCRIPT_DIR/uninstall.sh" --source "$SOURCE_DIR" --stop-only'),
    "dashboard-port conflicts must be rejected before the running instance is stopped",
  );
  assert.match(installer, /retire_previous_app/);
  assert.match(installer, /app_instance_id "\$CURRENT_INSTALL_APP"/);
  assert.match(installer, /\.Trash/);
  assert.match(installer, /--web-port/);
  assert.match(installer, /web-port/);
  assert.match(installer, /chmod 600/);
  assert.match(installer, /nodejs\.org\/download\/release/);
  assert.match(installer, /NODE_SHA256/);
  assert.match(installer, /shasum -a 256/);
  assert.match(installer, /runtime_is_valid/);
  assert.match(installer, /uuidgen/);
  assert.match(installer, /ensure_instance_id/);
  assert.match(installer, /NEW_INSTANCE_CONFIG/);
  assert.match(installer, /runner-port/);
  assert.match(installer, /instances\/\$INSTANCE_ID/);
  assert.match(installer, /--instance-id/);
  assert.match(installer, /Control Module \$\{INSTANCE_ID\[1,8\]\}\.app/);
  assert.match(uninstaller, /\.control-module-instance/);
  assert.match(uninstaller, /runner-port/);
  assert.match(uninstaller, /runtime-path/);
  assert.match(uninstaller, /--dry-run/);
  assert.match(uninstaller, /--stop-only/);
  assert.match(uninstaller, /Other Control Module folders, apps, shortcuts, browser data, and settings: keep/);
  assert.match(uninstaller, /process_uses_instance/);
  assert.doesNotMatch(uninstaller, /clear_browser_data/);
  assert.doesNotMatch(uninstaller, /APP_TARGETS|TOOL_TARGETS/);
  assert.doesNotMatch(uninstaller, /rm -rf/);
  assert.match(uninstaller, /\.Trash/);
  assert.match(uninstaller, /Refusing to operate/);
  assert.match(builder, /ControlModule\.icns/);
  assert.match(builder, /Launch\.applescript/);
  assert.match(builder, /lipo.*-thin arm64/);
  assert.match(builder, /ditto "\$RUNTIME_DIR"/);
  assert.match(builder, /Contents\/Resources\/instance-id/);
  assert.doesNotMatch(builder, /CFBundleURLTypes|AUTHORIZATION_SCHEME/);
  assert.match(builder, /CFBundleIdentifier io\.github\.mitchell-mos\.control-module\.instance\.\$INSTANCE_ID/);
  assert.match(builder, /codesign --force --deep --sign - "\$STAGING_APP"/);
  assert.match(builder, /xattr -d com\.apple\.FinderInfo "\$OUTPUT_APP"/);
  assert.match(builder, /codesign --verify --deep --strict "\$STAGING_APP"/);
  assert.match(plist, /NSAppleEventsUsageDescription/);
  assert.match(plist, /refresh or focus them after you restart a host/);
  assert.match(builder, /codesign --verify --deep "\$OUTPUT_APP"/);
  assert.match(setupBuilder, /osacompile/);
  assert.match(setupBuilder, /Setup\.app/);
  assert.match(setupBuilder, /lipo.*-thin arm64/);
  assert.match(setupBuilder, /LSRequiresNativeExecution/);
  assert.match(setupBuilder, /xattr -d com\.apple\.FinderInfo "\$OUTPUT_APP"/);
  assert.match(setupBuilder, /codesign --verify --deep --strict "\$STAGING_APP"/);
  assert.match(setupBuilder, /codesign --verify --deep "\$OUTPUT_APP"/);
  assert.match(setupSource, /Dashboard port/);
  assert.match(setupSource, /--web-port/);
  assert.match(setupSource, /Desktop access/);
  assert.match(setupSource, /Keep Desktop private/);
  assert.match(setupSource, /--desktop-access/);
  assert.match(setupSource, /support\/mac\/store\.sh/);
  assert.match(setupSource, /Control Module folder/);
  assert.doesNotMatch(setupSource, /installLocation is "Desktop"/);
  assert.match(setupSource, /Desktop shortcut/);
  assert.doesNotMatch(setupSource, /Control Module and Setup shortcuts/);
  assert.match(setupSource, /stay in the Control Module folder/);
  assert.match(setupSource, /dashboard, settings, and saved projects stay on this Mac/i);
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
  assert.match(removeBuilder, /xattr -d com\.apple\.FinderInfo "\$OUTPUT_APP"/);
  assert.match(removeBuilder, /codesign --verify --deep --strict "\$STAGING_APP"/);
  assert.match(removeBuilder, /codesign --verify --deep "\$OUTPUT_APP"/);
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
  assert.match(plist, /optional/);
  assert.match(plist, /LSRequiresNativeExecution/);
  assert.match(plist, /arm64/);
  assert.match(readme, /Desktop shortcut/);
  assert.match(readme, /Setup\.app/);
  assert.match(readme, /Uninstall\.app/);
  assert.match(readme, /signed and notarized/i);
  assert.match(readme, /directly from nodejs\.org/i);
});
