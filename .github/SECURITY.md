# Security policy

## Supported versions

Security fixes are applied to the latest release on the default branch.

## Reporting a vulnerability

Use GitHub's private security-advisory feature for this repository. If private reporting is unavailable, open a minimal issue requesting a private contact channel.

Do not place session tokens, saved commands, logs, usernames, filesystem paths, or exploit details in a public issue. Include the affected version, macOS version, reproducible steps, impact, and any suggested mitigation in the private report.

## Scope

Control Module is a single-user local command runner. Public hosting, multi-user deployment, reverse proxies, tunnels, port forwarding, and commands obtained from untrusted sources are outside the supported security model.

The complete trust boundaries and expected local capabilities are documented in [`support/docs/Security.md`](../support/docs/Security.md).
