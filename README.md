# Control Module

Control Module is an open-source, local-only dashboard for starting, stopping, and restarting development projects from one browser page. It is designed for a single user on their own computer.

Control Module does **not** require Codex, ChatGPT, OpenAI, or any other AI/LLM service. It does not include analytics, telemetry, advertising, accounts, cloud storage, or a remote backend.

## Requirements

- macOS 13 or newer
- Node.js 22.13 or newer
- pnpm 10 or newer (`corepack enable pnpm` can install it with supported Node.js distributions)
- Python 3.11 or newer
- `lsof`, `ioreg`, and `zsh`, which are included with macOS

A packaged `Control Module.app` can include the standard open-source Node.js runtime. In that case, double-clicking the app does not require a system Node.js or pnpm installation. Source checkouts still use the requirements above to install dependencies and create a build.

## Install and run

```sh
git clone <your-repository-url>
cd control-module
pnpm install --frozen-lockfile
pnpm run build
chmod +x ControlModule
./ControlModule
```

The launcher starts the dashboard at `http://127.0.0.1:1025` and the private command runner at `http://127.0.0.1:10001`. Both services bind only to the loopback interface. On first graphical launch, Control Module can ask permission to install packages and build the dashboard for you.

No AI software is involved. A packaged app prefers its bundled standard Node.js runtime; a source checkout uses ordinary `node`, `pnpm`, and `python3` installations on the user's system.

## What it does on your computer

Control Module has the same authority as the macOS account that launches it. It intentionally:

- runs commands that you explicitly save and start through `/bin/zsh -c`;
- reads local TCP listener information with `lsof` to verify that a newly opened port belongs to the process group it started;
- sends `SIGTERM` to managed process groups when you stop them, waits five seconds, and uses `SIGKILL` only if that same managed process group does not exit;
- checks the macOS console lock flag with `ioreg` every five seconds and stops managed projects after the Mac remains locked for 15 minutes;
- stores project settings and local command output on disk.

Control Module does not scan arbitrary files, upload data, contact an AI service, or signal processes that it did not launch and verify. Commands run with a minimal environment instead of inheriting tokens or unrelated environment variables from the launcher.

## Private local data

These files are created at runtime and are excluded by `.gitignore`:

| Path | Contents | Permissions |
|---|---|---|
| `control-projects.json` | Project names, ports, and commands | `0600` |
| `control-logs/` | Per-project command output with rotation | directory `0700`, files `0600` |
| `.control-runtime/session-token` | Random token authorizing this browser session; rotated when the runner starts | `0600` |
| `control-module.log` | Local dashboard startup output | created under a private launcher umask |
| `control-runner.log` | Local runner diagnostics | created under a private launcher umask |

Commands themselves are not copied into the per-project output logs. Logs rotate at 2 MiB and retain up to three prior files. Delete the paths above while Control Module is stopped to remove all saved local data.

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

Please report vulnerabilities according to [SECURITY.md](SECURITY.md). Do not include private commands, tokens, logs, or filesystem paths in public reports.

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

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change.

## Disclaimer & intended use

This software is a **local, web-based terminal controller** designed strictly for local execution.

- **No warranty:** This software is provided “as is,” without warranty of any kind, express or implied. You use this tool entirely at your own risk. The author assumes no responsibility or liability for misuse, damage, data loss, security incidents, or system issues arising from its use.
- **Server hosting warning:** This tool is **not** engineered or intended to be exposed as a public-access network service or multi-tenant Software-as-a-Service (SaaS). Hosting it publicly without substantial independent security hardening is strongly discouraged and may compromise the host system or its data.
- **User responsibility:** You are responsible for reviewing every command, dependency, network configuration, and modification before running it.

The full legal warranty and liability terms are in the [MIT License](LICENSE).

## License

Copyright © 2026 Mitchell Moscoso.

Control Module is released under the [MIT License](LICENSE). Redistributions must retain the copyright and license notice.

Third-party icon notices are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Packaged runtime version, checksum, and download provenance are recorded in [BUNDLED_RUNTIME.md](BUNDLED_RUNTIME.md).
