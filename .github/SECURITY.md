# Security policy

## Supported versions

Security fixes are applied to the latest release on the default branch.

## Reporting a vulnerability

Report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/mitchell-mos/Local-Terminal-Web-Based-Control-Module-/security/advisories/new). If that form is unavailable, open a minimal public issue requesting a private contact channel without including technical details.

Do not place session tokens, saved commands, logs, usernames, filesystem paths, or exploit details in a public issue. Include the affected version, macOS version, reproducible steps, impact, and any suggested mitigation in the private report.

## Response and disclosure

The maintainer aims to acknowledge a vulnerability report within 7 days and provide a status update at least every 14 days while it is being investigated. A coordinated disclosure date will be agreed with the reporter; the usual target is within 90 days, but active exploitation or a readily available fix may require an earlier disclosure.

Please keep vulnerability details private until a fix or mitigation is available. After remediation, the maintainer may publish a GitHub security advisory describing the affected versions, impact, fix, and reporter credit when requested.

## Scope

Control Module is a single-user local command runner. Public hosting, multi-user deployment, reverse proxies, tunnels, port forwarding, and commands obtained from untrusted sources are outside the supported security model.

The complete trust boundaries and expected local capabilities are documented in [`support/docs/Security.md`](../support/docs/Security.md).
