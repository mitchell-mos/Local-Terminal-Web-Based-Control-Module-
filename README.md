# Control Module

Control Module is an open-source, local-only dashboard for starting, stopping, and restarting development projects from one browser page. It is designed for a single user on their own computer.

Control Module does **not** require Codex, ChatGPT, OpenAI, or any other AI/LLM service. It does not include analytics, telemetry, advertising, accounts, cloud storage, or a remote backend.

## Requirements

- Apple silicon Mac (M1 or newer); Intel Macs and Rosetta are not supported
- macOS 13 or newer
- Node.js 22.13 or newer
- pnpm 10 or newer (`corepack enable pnpm` can install it with supported Node.js distributions)
- Python 3.11 or newer
- `lsof`, `ioreg`, and `zsh`, which are included with macOS

Setup downloads the official ARM64 Node.js runtime directly from nodejs.org when it is not already cached, verifies its pinned SHA-256 checksum, and includes the complete runtime in `Control Module.app`. Double-clicking the installed app therefore does not require a system Node.js or pnpm installation. Python 3.11 or newer is still required for the local command runner. No runtime is obtained from Codex, ChatGPT, or another LLM.

## Install and run

### Guided macOS setup

After downloading or cloning the project, double-click `Setup.app`. It uses native macOS prompts without opening Terminal and lets you:

- choose the dashboard port, with `1025` as the recommended default;
- choose whether normal launches keep Desktop private or use the live Desktop checkout;
- install the real launcher in the Control Module folder or your personal Applications folder;
- optionally create a Desktop shortcut for Control Module;
- optionally open Control Module as soon as setup finishes.

Setup automatically verifies the Control Module checkout that contains it; it never asks you to select arbitrary files or folders in Finder. The default **Keep Desktop private** source mode runs a private working copy from the installation's Application Support directory, regardless of where the launcher itself is installed. Opening Control Module then does not read its Desktop checkout. **Allow access** runs directly from the downloaded folder and lets macOS present its standard Desktop authorization prompt. Source mode does not grant or revoke an existing macOS Files & Folders permission; review that separately in System Settings → Privacy & Security → Files & Folders. Rerun Setup whenever you want to change this mode or the dashboard port. A saved project command that explicitly targets Desktop may still cause macOS to ask when that project starts, regardless of the launch mode.

Setup records the verified checkout, private runtime path, access mode, installation path, and ports under `~/Library/Application Support/Control Module/` with permissions limited to your account. These local records are outside the repository, so personal filesystem paths are not committed or published. If you move the checkout, move Setup with it and run Setup again. The native apps use the same gear artwork as the web interface.

Setup keeps one real `Setup.app` in the Control Module folder and does not place Setup on the Desktop. If the Desktop shortcut is selected, it links only to the real Control Module app rather than creating a duplicate app bundle. To change the port or reinstall later, open `Setup.app` from the Control Module folder.

The dashboard's **More → Settings** option shows the current port, source mode, shortcut state, install location, and appearance. Opening native settings requires a confirmation before the authenticated loopback runner launches the verified `Setup.app` belonging to the same installation. Uninstall uses a separate warning, opens only the verified `Uninstall.app`, and then relies on that native app's second confirmation before anything is moved to Trash. The browser API never grants macOS permissions, edits installation settings directly, or deletes files.

The **Add project** window starts in Basic mode. You can browse for a folder or enter its full path; Control Module reads only that folder's top-level `package.json` (when present) and lockfile names to recognize static files, Vite-compatible projects, Astro, SvelteKit, Next.js, and custom package scripts. It selects npm, pnpm, Yarn, or Bun from the declared package manager or project lockfile and displays a shell-escaped command for review. pnpm and Yarn commands use the bundled Node.js Corepack launcher. Basic mode never installs packages or starts the project automatically. Advanced mode keeps the Start command required and adds optional Setup, Stop, and Restart commands for projects with custom process lifecycles.

Use **App functions → More → Export projects** to move project definitions between Control Module installations, then use **Import projects** from the same menu on the destination. Export creates a versioned JSON file containing project names, ports, and saved lifecycle commands only; it excludes runtime IDs, process IDs, logs, status, tokens, timestamps, themes, and application settings. Import validates the file, assigns fresh project IDs, rechecks every destination port, skips conflicts instead of silently changing them, and leaves every imported project stopped. Export files can contain private filesystem paths and arbitrary shell commands, so review them before importing and do not publish them unless you have removed sensitive information.

When you change the install location, Setup verifies the previous launcher's internal installation marker, installs and records the replacement first, updates its shortcut, and then moves only that superseded launcher to Trash. Other Control Module installations and unrelated apps are untouched.

On first setup, each downloaded Control Module folder receives a random, non-secret internal installation marker. The same marker is recorded in the folder, installed app bundle, and private settings directory. Setup detects a Finder copy carrying another folder's marker and assigns the copy a new one. Source files are not individually modified or stamped with a secret; folder membership plus matching ownership markers provides the uninstall boundary without corrupting project files or exposing the private runner token.

Each installation receives its own settings, saved projects, logs, rotating private runner token, dashboard port, and automatically selected private runner port. Multiple copies can therefore run at the same time when their dashboard ports differ. If the standard Applications or Desktop app name is already owned by another installation, Setup adds a short marker to the app name instead of overwriting it.

Bookmarks and dashboard URLs contain only the loopback address, such as `http://127.0.0.1:1025/`. The internal installation marker, private runner port, and authorization token are not shown or saved in the browser. Any browser on the same Mac can open that address without a separate authorization prompt while Control Module is running. The dashboard validates the local request and forwards it to the private runner with the rotating token on the server side. If the dashboard is not running, open `Control Module.app` first.

The generated apps contain ARM64-only launch executables, require native execution, and use the ARM64 Node.js runtime when one is bundled. The generated app is ad-hoc signed for local use. Public downloadable releases should be signed and notarized with an Apple Developer ID before distribution; otherwise macOS may show an unidentified-developer warning.

Maintainers can regenerate the native icon from `public/gear.svg` with `support/mac/icon.sh` and rebuild the native setup app with `support/mac/setup.sh`.

### Terminal setup

```sh
git clone <your-repository-url>
cd control-module
pnpm install --frozen-lockfile
pnpm run build
chmod +x ControlModule
./ControlModule
```

### Uninstall

Double-click the `Uninstall.app` inside the Control Module folder you want to remove. Its trash-can icon distinguishes this destructive action from Setup and the main app. It presents one confirmation with clear No and Yes choices. Choosing Yes moves only that verified Control Module folder to Trash. If that exact folder is the configured running copy, its local services and managed projects are stopped safely first.

Other downloaded Control Module folders, apps in Applications, Desktop shortcuts, browser storage, shared settings, saved commands, logs, tokens, backups, external project folders, and databases are left unchanged. This narrow behavior prevents one downloaded copy from uninstalling another. A shortcut that pointed into the removed folder may become broken and can be deleted manually. Empty the Trash later to erase the removed folder permanently.

Maintainers can preview the exact native-app uninstall without changing anything by running `support/mac/uninstall.sh --source "$PWD" --remove-source --dry-run`.

The launcher starts the dashboard at the port selected during Setup and an automatically assigned private command-runner port. Both services bind only to the loopback interface. On first graphical launch, Control Module can ask permission to install packages and build the dashboard for you.

No AI software is involved. A packaged app prefers its bundled standard Node.js runtime; a source checkout uses ordinary `node`, `pnpm`, and `python3` installations on the user's system.

## Project layout

| Path | Purpose |
|---|---|
| `app/` | Browser interface and styling |
| `server/` | Loopback-only Python command runner |
| `lib/` | Shared security headers and utilities |
| `public/` | Local interface icons and static assets |
| `support/docs/` | Runtime and third-party notes |
| `support/mac/` | Native app assets and tools |
| `support/tests/` | JavaScript and Python tests |
| `.github/` | GitHub guides and workflows |
| `ControlModule` | Source and packaged-app launcher |
| `Setup.app` | Guided setup; remains the single real Setup app in the project folder |
| `Uninstall.app` | Native guided removal |

The root keeps only launch/runtime source and files that GitHub, Node.js, pnpm, TypeScript, or Vite require at standard paths. Auxiliary files live under `support/` with short names.

## What it does on your computer

Control Module has the same authority as the macOS account that launches it. It intentionally:

- runs commands that you explicitly save and start through `/bin/zsh -c`;
- opens a macOS folder picker only when requested and inspects only the explicitly selected folder's top-level `package.json` and package-manager lockfile names to generate a Basic-mode command;
- reads local TCP listener information with `lsof` to verify that a newly opened port belongs to the process group it started;
- sends `SIGTERM` to managed process groups when you stop them, waits five seconds, and uses `SIGKILL` only if that same managed process group does not exit;
- checks the macOS console lock flag with `ioreg` every five seconds and stops managed projects after the Mac remains locked for 15 minutes;
- stores project settings and local command output on disk.

Control Module does not crawl project folders, upload data, contact an AI service, install detected project dependencies, or signal processes that it did not launch and verify. Commands run with a minimal environment instead of inheriting tokens or unrelated environment variables from the launcher.

## Private local data

Normal launches keep private state outside the repository under `~/Library/Application Support/Control Module/instances/<instance-id>/`. The UUID is an internal installation marker used for ownership checks, not an authentication secret or a value users need to manage.

| Path | Contents | Permissions |
|---|---|---|
| `.control-module-instance` in the downloaded folder | Non-secret internal installation marker; ignored by Git | `0600` |
| `instance-id` | Matching ownership UUID | `0600` |
| `project-path` | Verified checkout belonging to this installation | `0600` |
| `runtime-path` | Live checkout or private working copy selected in Setup | `0600` |
| `desktop-access` | Saved `private` or `desktop` launch mode | `0600` |
| `install-path` | Installed app carrying the same internal marker | `0600` |
| `web-port` | Dashboard port selected during Setup | `0600` |
| `runner-port` | Private runner port assigned to this installation | `0600` |
| `data/projects.json` | Project names, ports, and commands for this installation | `0600` |
| `data/logs/projects/` | Project output for this installation, with rotation | directory `0700`, files `0600` |
| `data/runtime/session-token` | Random server-side runner secret rotated when the runner starts | `0600` |
| `data/logs/dashboard.log` | Dashboard startup output for this installation | `0600` |
| `data/logs/runner.log` | Runner diagnostics for this installation | `0600` |
| `data/backups/` | Private safety copies for this installation | directory `0700`, files `0600` |

Commands themselves are not copied into the per-project output logs. Logs rotate at 2 MiB and retain up to three prior files. The launcher safely migrates data from older root-level locations on first run. Delete `~/Library/Application Support/Control Module/` while Control Module is stopped to remove all saved local settings and data.

Before publishing a fork, review staged files with:

```sh
git status --short
git diff --cached --stat
git diff --cached
```

Never commit runtime JSON, logs, `.env` files, tokens, or project-specific filesystem paths.

## Security model

- The dashboard and runner are loopback-only and are not intended to accept LAN or internet traffic.
- The browser sends API requests only to the dashboard's own loopback origin. The dashboard rejects invalid hosts, origins, and cross-site browser requests, then forwards accepted calls to the private runner with a random token read from its private local data directory. The runner independently validates its exact local Origin, Host, and rotating token. The browser, page URL, bookmarks, and Web Storage never receive that token.
- Saved Start, Setup, Stop, and Restart commands are arbitrary shell commands. Only run commands you understand and trust. Setup runs before Start and Restart; Stop runs before Control Module's managed process-group shutdown; a saved Restart command is used in place of Start after the old host closes.
- Basic-mode commands are generated locally, shown before saving, and do not run until you press Start. Selecting a package script means trusting that script and its installed dependencies.
- Control Module is not a sandbox, container, permissions boundary, remote administration panel, or multi-user service.
- A project command can still read or change anything the current macOS user can access. Review commands before starting them.
- Do not expose either port through a reverse proxy, tunnel, router, public server, or port-forwarding rule.

Please report vulnerabilities according to the [security policy](.github/SECURITY.md). Do not include private commands, tokens, logs, or filesystem paths in public reports.

## Development

```sh
pnpm install --frozen-lockfile
pnpm run dev
```

Run the complete local verification suite with:

```sh
pnpm test
pnpm run build
pnpm audit
```

See the [contribution guide](.github/CONTRIBUTING.md) before submitting a change.

## Disclaimer & intended use

This software is a **local, web-based terminal controller** designed strictly for local execution.

- **No warranty:** This software is provided “as is,” without warranty of any kind, express or implied. You use this tool entirely at your own risk. The author assumes no responsibility or liability for misuse, damage, data loss, security incidents, or system issues arising from its use.
- **Server hosting warning:** This tool is **not** engineered or intended to be exposed as a public-access network service or multi-tenant Software-as-a-Service (SaaS). Hosting it publicly without substantial independent security hardening is strongly discouraged and may compromise the host system or its data.
- **User responsibility:** You are responsible for reviewing every command, dependency, network configuration, and modification before running it.

The full legal warranty and liability terms are in the [MIT License](LICENSE).

## License

Copyright © 2026 Mitchell Moscoso.

Control Module is released under the [MIT License](LICENSE). Redistributions must retain the copyright and license notice.

Third-party icon notices are listed in [support/docs/Notices.md](support/docs/Notices.md).
Packaged runtime version, checksum, and download provenance are recorded in [support/docs/Runtime.md](support/docs/Runtime.md).
