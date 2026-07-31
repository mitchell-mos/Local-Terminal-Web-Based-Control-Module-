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
- install the real launcher in the Control Module folder or your personal Applications folder;
- optionally create a Desktop shortcut for Control Module;
- optionally open Control Module as soon as setup finishes.

Setup automatically verifies the Control Module checkout that contains it; it never asks you to select arbitrary files or folders in Finder. It records that verified project path, the installation path, and dashboard port in `~/Library/Application Support/Control Module/` with permissions limited to your account. These local records are outside the repository, so personal filesystem paths are not committed or published. Rerun Setup whenever you want to change the dashboard port. If you move the checkout, move Setup with it and run Setup again. The native apps use the same gear artwork as the web interface.

Setup keeps one real `Setup.app` in the Control Module folder and does not place Setup on the Desktop. If the Desktop shortcut is selected, it links only to the real Control Module app rather than creating a duplicate app bundle. To change the port or reinstall later, open `Setup.app` from the Control Module folder.

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

The launcher starts the dashboard at the port selected during Setup and the private command runner at `http://127.0.0.1:10001`. Both services bind only to the loopback interface. On first graphical launch, Control Module can ask permission to install packages and build the dashboard for you.

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
- reads local TCP listener information with `lsof` to verify that a newly opened port belongs to the process group it started;
- sends `SIGTERM` to managed process groups when you stop them, waits five seconds, and uses `SIGKILL` only if that same managed process group does not exit;
- checks the macOS console lock flag with `ioreg` every five seconds and stops managed projects after the Mac remains locked for 15 minutes;
- stores project settings and local command output on disk.

Control Module does not scan arbitrary files, upload data, contact an AI service, or signal processes that it did not launch and verify. Commands run with a minimal environment instead of inheriting tokens or unrelated environment variables from the launcher.

## Private local data

Normal launches keep private state outside the repository under `~/Library/Application Support/Control Module/`:

| Path | Contents | Permissions |
|---|---|---|
| `project-path` | Verified Control Module checkout detected by Setup | `0600` |
| `install-path` | Location of the locally installed app | `0600` |
| `web-port` | Dashboard port selected during Setup | `0600` |
| `data/projects.json` | Project names, ports, and commands | `0600` |
| `data/logs/projects/` | Per-project command output with rotation | directory `0700`, files `0600` |
| `data/runtime/session-token` | Random token authorizing this browser session; rotated when the runner starts | `0600` |
| `data/logs/dashboard.log` | Local dashboard startup output | `0600` |
| `data/logs/runner.log` | Local runner diagnostics | `0600` |
| `data/backups/` | Private safety copies of unreadable or older project data | directory `0700`, files `0600` |

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
- The runner requires an exact local Origin, Host validation, and a random token that is rotated when the runner starts. The launcher passes it in a URL fragment, which is not sent in HTTP requests, and the page immediately moves it to tab-only session storage.
- Saved commands are arbitrary shell commands. Only run commands you understand and trust.
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
