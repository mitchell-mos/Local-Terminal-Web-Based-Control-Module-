# Control Module

Control Module is an open-source, local-only dashboard for starting, stopping, and restarting development projects from one browser page. It is designed for one person using their own Apple silicon Mac.

It does not include analytics, telemetry, advertising, accounts, cloud storage, or a remote backend.

## Requirements

- Apple silicon Mac (M1 or newer); Intel Macs and Rosetta are not supported
- macOS 13 or newer
- Python 3.11 or newer
- Node.js 22.13 or newer and the pinned pnpm 11.9.0 for source development

Guided Setup downloads the official Node.js 24.17.0 ARM64 runtime directly from nodejs.org, verifies its pinned checksum, and stores the tools required by the installed app. A system Node.js or pnpm installation is not required after Setup finishes. See [runtime provenance](support/docs/Runtime.md).

## Install

Download the ARM64 archive from [GitHub Releases](https://github.com/mitchell-mos/Local-Terminal-Web-Based-Control-Module-/releases), keep `Setup.app` inside its extracted Control Module folder, and double-click it. Setup lets you:

- review whether this copy is installed, running, stopped, or ready for an update;
- manually check the latest published GitHub release without sending project data or settings;
- select the dashboard port, with `1025` recommended;
- use a private Application Support working copy or the downloaded checkout;
- install the launcher in the project folder or your personal Applications folder;
- optionally create one Desktop shortcut; and
- optionally open Control Module when installation finishes; and
- safely start, stop, restart, or refresh the status of an existing installation.

Setup verifies the checkout containing it and never asks you to select arbitrary Control Module files in Finder. It compares versions numerically and blocks an older or unverifiable download from replacing a newer installation. Private mode keeps project definitions, logs, settings, and the optimized standalone dashboard under `~/Library/Application Support/Control Module/instances/<instance-id>/` with access limited to your account.

Rollback protection is enforced by Setup v1.04.0 and later. Software downloaded before that protection was added cannot gain it retroactively, so discard older Setup archives after upgrading and open Setup only from a verified current release.

The installed app opens `http://127.0.0.1:<selected-port>/`. If it is already running, opening the app focuses the existing dashboard instead of creating a second service.

## Updates

Open **Settings → Open app settings**, then press **Check GitHub for updates**. Setup prefers the latest packaged release; if none has been published yet, it compares against `version.json` on the repository's `main` branch and clearly labels that result as source code. It never downloads, installs, or runs an update automatically.

For a packaged installation, download the newer ARM64 archive from GitHub Releases and run the Setup inside that extracted folder. For a source clone, review local changes first, update with `git pull --ff-only`, rebuild with the development commands below, and run the rebuilt Setup. Running Setup preserves that installation's saved projects, settings, and logs. Do not replace files from an untrusted fork merely because its version number is higher.

For source development:

```sh
git clone <your-repository-url>
cd control-module
corepack pnpm install --frozen-lockfile
corepack pnpm run build
zsh support/mac/setup.sh
zsh support/mac/remove.sh
chmod +x ControlModule
./ControlModule
```

The native Setup and Uninstall apps are generated from reviewable Objective-C, AppleScript, property-list, and shell sources under `support/mac/`. Generated app bundles are release artifacts and are intentionally not committed to the source repository.

Each packaged release includes a SHA-256 checksum and GitHub build-provenance attestation. You can verify them before opening Setup:

```sh
shasum -a 256 -c Control-Module-v1.04.2-macOS-arm64.zip.sha256
gh attestation verify Control-Module-v1.04.2-macOS-arm64.zip --repo mitchell-mos/Local-Terminal-Web-Based-Control-Module-
```

## Projects

**Add project** offers two modes:

- **Basic** inspects the selected folder's top-level package metadata and generates a reviewable command for static files, Vite-compatible projects, Astro, SvelteKit, Next.js, or custom package scripts.
- **Advanced** accepts a required Start command and optional Setup, Stop, and Restart lifecycle commands.

Commands do not run until you press Start. A project may also include a published `http://` or `https://` address. Search, filters, sorting, and list/card view are saved in that browser. Import and export move project definitions as JSON without tokens, logs, process IDs, themes, or app settings; exported commands may still contain private paths, so review them before sharing.

Restart can refresh matching Safari and Chromium-family tabs by their saved local port while preserving nested routes. macOS may request Automation permission during that explicit action. Control Module does not read page contents or browsing history.

## Uninstall

Double-click `Uninstall.app` inside the Control Module folder you want to remove. After one confirmation, it moves only that verified downloaded folder to Trash and safely stops services owned by that installation when necessary.

Other Control Module copies, external project folders, shared Application Support settings, browser preferences, and unrelated files are left unchanged. See [troubleshooting](support/docs/Troubleshooting.md) if Setup, launch, or removal does not behave as expected.

## Security and privacy

Control Module has the same authority as the macOS account that launches it. Saved commands run through `/bin/zsh -c`. Managed process groups receive `SIGTERM`, followed by `SIGKILL` only when the same verified group has not exited after five seconds.

The dashboard and runner bind only to loopback. Browser requests are checked by host, origin, and fetch site; the dashboard forwards approved API calls to the runner with a rotating private token held on the server side. That token is never placed in the URL, page, bookmarks, or Web Storage. Any browser on the same Mac can use the dashboard address while the app is running.

Setup contacts GitHub only when you press **Check GitHub for updates**. Those unauthenticated requests ask for the latest public release tag and, when no release exists, the public `version.json` on `main`; they do not include saved projects, commands, paths, logs, settings, or tokens. GitHub still receives ordinary connection metadata such as the requester’s IP address. Control Module never downloads or installs an application update automatically.

Control Module is not a sandbox, permissions boundary, remote administration panel, public server, or multi-user SaaS. Do not expose either local port through a tunnel, reverse proxy, router, or port-forwarding rule. Read the complete [security model and threat boundaries](support/docs/Security.md), and report vulnerabilities according to the [security policy](.github/SECURITY.md).

## Repository layout

| Path | Purpose |
|---|---|
| `app/` | Browser interface, reusable controls, and styling |
| `server/` | Loopback-only Python runner and browser-tab integration |
| `lib/` | Shared headers and release metadata |
| `public/` | Local interface icons |
| `support/mac/` | Native setup, launcher, uninstall, and release tools |
| `support/tests/` | JavaScript and Python checks |
| `support/docs/` | Architecture, security, runtime, and troubleshooting details |
| `.github/` | Contribution policy and automated verification |

The runtime flow and ownership model are documented in [Architecture.md](support/docs/Architecture.md). Generated builds, private runtime data, design notes, logs, environment files, and local development tools are excluded by `.gitignore`.

## Development

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm test
corepack pnpm run build
corepack pnpm audit
```

Pull requests run the same test/build suite on Linux plus ARM launcher, plist, signing, and process-control checks on macOS. CodeQL, dependency review, Dependabot, and OpenSSF Scorecard cover security and dependency changes. See [CONTRIBUTING.md](.github/CONTRIBUTING.md).

Maintainers can build a clean, checksum-stamped ARM64 archive after committing changes. Pushing a matching version tag runs the same builder on GitHub's ARM64 macOS runner, publishes the archive and checksum, and records build provenance:

```sh
support/mac/release.sh
```

Public releases should be signed and notarized with an Apple Developer ID. Local builds are ad-hoc signed.

## Versions

The footer uses `vMAJOR.UPDATE.FIX`, such as `v1.00.0`:

- `MAJOR` is a compatibility break or security-model change;
- `UPDATE` is a regular feature or workflow release; and
- `FIX` is a small correction within an update.

`version.json` is user-facing; `package.json` uses ordinary unpadded semantic versioning. Before opening or updating a release pull request, run exactly one of:

```sh
corepack pnpm version:bump major
corepack pnpm version:bump update
corepack pnpm version:bump fix
```

The version workflow verifies one valid transition against the pull request's base. Automated dependency-maintenance pull requests do not publish unrelated app releases. Changes are summarized in [CHANGELOG.md](CHANGELOG.md).

## Disclaimer and intended use

This software is a local, web-based terminal controller designed strictly for local execution. It is provided “as is,” without warranty of any kind. You are responsible for reviewing commands, dependencies, network configuration, and modifications before running them. Public or multi-user hosting is unsupported and may compromise the host system or its data.

## License

Copyright © 2026 Mitchell Moscoso.

Control Module is released under the [MIT License](LICENSE). Redistributions must retain the copyright and license notice. Third-party icon and runtime terms are listed in [Notices.md](support/docs/Notices.md).
