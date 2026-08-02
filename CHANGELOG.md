# Changelog

Notable user-facing changes are recorded here. Versions use `vMAJOR.UPDATE.FIX`.

## Unreleased

- No unreleased changes.

## v1.01.2

- Resolved CodeQL findings in URL-oriented test assertions, test-server initialization, and theme-state setup.
- Clarified intentionally ignored filesystem and process-race exceptions without changing runtime behavior.
- Simplified corrupt-project backup state tracking and Python test imports.

## v1.01.1

- Fixed the release-version check so automated dependency maintenance can merge without publishing an unrelated app release.
- Kept exact version-increment enforcement for regular release pull requests.

## v1.01.0

- Added persistent project filtering, optional published-site links, clearer project reordering, and improved restart behavior.
- Added release versioning and the application footer.
- Added pull-request CI, stricter dependency review, expanded CodeQL analysis, and weekly dependency updates.
- Added schema-checked project storage, bounded dashboard requests, credential redaction for browser error summaries, and batched listener checks.
- Improved keyboard behavior for process tabs and action menus, high-contrast support, and notification announcements without changing the visual layout.
- Reduced private dashboard installations from a full development dependency tree to a production standalone bundle.
- Added clean ARM64 release packaging, architecture and security documentation, troubleshooting, and this changelog.

## v1.00.0

- Initial public release of the local project-control dashboard, native Setup, and scoped Uninstall.
