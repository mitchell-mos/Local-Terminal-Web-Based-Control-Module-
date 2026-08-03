# Security model

## Supported use

Control Module is a single-user local development tool. The supported deployment is one Apple silicon Mac, one macOS user account, and loopback-only ports. Public hosting, LAN exposure, tunnels, reverse proxies, port forwarding, shared accounts, and multi-user operation are outside the threat model.

## Trust boundaries

- A saved lifecycle command is arbitrary shell code with the current macOS user's permissions. Review it before running it.
- Any browser or process in the same macOS user environment may reach the dashboard while it is running. The browser does not hold a reusable runner credential.
- The dashboard rejects unexpected Host, Origin, and cross-site browser requests. The runner independently requires an exact Host, Origin, and rotating private token.
- A malicious local process running as the same user is not fully isolated by loopback or file permissions.

## Filesystem access

Basic project inspection accepts an absolute path, resolves symbolic links and traversal, requires the result to remain inside the user's home directory, rejects a symbolic-link `package.json`, and reads only supported top-level metadata. Runtime data uses private permissions and atomic replacement.

Setup and Uninstall verify package identity, app bundle identifiers, canonical paths, matching installation markers, and installation-owned runtime paths before modifying anything. Setup blocks a downloaded version that is older than or cannot be safely compared with an existing installation. Uninstall targets one verified downloaded folder and never recursively removes a broad home, Desktop, Applications, or workspace path.

Rollback protection begins with Setup v1.04.0. An installer downloaded before that control existed cannot enforce a future policy, and version metadata from an untrusted fork is not proof of authenticity. Discard superseded installers and verify release checksums and build provenance before running Setup.

## Processes and ports

The runner tracks the exact `Popen` object and process-group ID it created. Listener ownership is checked with `lsof`; stop operations signal only the verified group. Reserved, browser-blocked, duplicate, system, dashboard, runner, and currently occupied project ports are rejected.

The Mac lock monitor reads only the system console lock flag. After 15 continuous locked minutes it stops managed projects; logging out or shutting down terminates the local services through normal process cleanup.

## Privacy

The application does not include analytics, telemetry, advertising, cloud storage, accounts, or an external application backend. Setup's documented Node.js download, its user-initiated GitHub update check, and links explicitly opened by the user are the expected external network actions. The update check requests only the latest public release tag and, when no release exists, the public `version.json` on `main`. It sends no local project data, settings, logs, paths, commands, or tokens; GitHub receives ordinary connection metadata such as the requester's IP address.

Project definitions, commands, local paths, logs, settings, and tokens stay on disk. Export files intentionally include saved commands and may therefore contain private paths. Error summaries shown in the interface redact common credential assignments, but users should still remove private details from screenshots and reports.

## Reporting

Use the repository's private security-advisory feature. Do not place commands, logs, tokens, usernames, filesystem paths, or working exploit details in a public issue. See [.github/SECURITY.md](../../.github/SECURITY.md).
