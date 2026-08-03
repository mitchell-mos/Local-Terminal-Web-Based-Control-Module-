# Architecture

Control Module has two loopback services and one native launcher:

1. `ControlModule` validates the installation, starts the services, and opens the selected dashboard port.
2. The Vinext standalone server serves the React interface and proxies same-origin `/api/` requests.
3. `server/control_server.py` owns project records, process groups, port checks, logs, and native macOS integrations.

The browser never receives the runner's private port or token. The dashboard reads the rotating token from the installation's private data directory and injects it only while proxying an approved request to the runner.

## Process lifecycle

Start and Restart commands run in new process groups with a small environment allowlist. A project is shown as running only when its process group is alive, its saved port responds, and one listener on that port belongs to the same process group. Project-list refreshes use one `lsof` snapshot for all saved ports.

Stop runs the optional saved Stop hook, sends `SIGTERM` to the verified group, waits up to five seconds, and uses `SIGKILL` only when that group remains alive. Control Module never kills an arbitrary process merely because it occupies the same port.

## Storage

Each installed copy has a non-secret UUIDv4 ownership marker. Matching markers in the downloaded folder, app bundle, and settings directory prevent Setup or Uninstall from changing another copy.

Private data lives in `~/Library/Application Support/Control Module/instances/<instance-id>/` with directories set to `0700` and files set to `0600`. `projects.json` is size-, count-, schema-, ID-, timestamp-, and port-validated before use. Invalid data is preserved unchanged with a private backup.

Project output rotates at 2 MiB with three backups. Error summaries redact common token, password, authorization, secret, and API-key assignments before they reach the browser; the full private log remains unchanged for diagnosis.

## Installation footprint

Source development uses the full dependency tree. Production builds use Vinext's standalone output, which contains only the generated dashboard, Vinext production server, and runtime packages. Private installations discard build dependencies after a successful standalone build.

Setup verifies the official Node.js ARM64 archive before extraction. It keeps Node, npm, Corepack, and licenses needed for first-run source builds, but removes C/C++ headers, manuals, and release documentation that the application does not execute.

The native Setup window reads status through `support/mac/manage.sh`. A shared version helper compares major, update, and fix numbers in order; both the interface and installer reject downgrades independently. The optional update check prefers the latest public GitHub release tag, falls back to public `version.json` on `main` when no release exists, and never installs anything. Lifecycle actions resolve the current installation marker and constrain saved runtime paths before operating. Stop reuses the scoped uninstall backend's `--stop-only` path; Restart performs that same safe stop before reopening only the matching installed app.

## Boundaries

- The product supports Apple silicon and macOS 13 or newer.
- The dashboard and runner support loopback only.
- Project folders must resolve inside the current user's home directory.
- Basic inspection reads only the selected directory's top-level package metadata and lockfile names.
- Arbitrary saved commands are trusted user input, not sandboxed code.
