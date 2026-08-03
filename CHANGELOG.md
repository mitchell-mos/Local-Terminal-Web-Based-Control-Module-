# Changelog

Notable user-facing changes are recorded here. Versions use `vMAJOR.UPDATE.FIX`.

## Unreleased

- No unreleased changes.

## v1.04.0

- Replaced the sequential Setup dialogs with a larger native macOS interface that detects and explains existing installations.
- Added ownership-checked status, Start, Stop, and Restart controls to Setup, including confirmation and in-progress cancellation states.
- Made Setup re-check the installation when reopened, while preserving unsaved form choices.
- Made the app and Desktop shortcut focus a healthy existing dashboard instead of launching duplicate services.
- Detached lifecycle starts from Setup and launcher parent processes so closing either interface does not stop healthy services.
- Added an explicit GitHub release check that runs only when requested and discloses its limited network behavior.
- Added numeric version ordering, strict metadata consistency checks, and defense-in-depth downgrade blocking in both Setup and its installer.
- Constrained lifecycle runtime paths, tightened package and install-destination verification, and stopped Basic inspection from following a symlinked package manifest.

## v1.02.1

- Renamed the property-based fuzz suite to a JavaScript extension recognized by OpenSSF Scorecard while keeping it in the regular test run.

## v1.02.0

- Added property-based fuzz tests for release metadata and version transitions.
- Removed generated native executables from source control; CI and release packaging now rebuild and verify Setup and Uninstall from their reviewable sources.
- Strengthened GitHub Actions token defaults, declared code ownership, and expanded the private vulnerability-reporting policy.
- Added an ARM64 release workflow with checksums and GitHub build-provenance attestations, plus matching installation documentation.

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
