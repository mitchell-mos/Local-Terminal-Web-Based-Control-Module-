# Contributing

Contributions are welcome under the MIT License.

1. Do not commit personal project data, commands, logs, tokens, `.env` files, absolute home-directory paths, or generated build output.
2. Install the documented Node.js, pnpm, and Python versions, then run `pnpm install --frozen-lockfile`.
3. Keep the dashboard and runner bound to loopback. Changes that expose shell execution over a network will not be accepted.
4. Add or update tests for behavior changes.
5. Classify the largest included change and run `pnpm version:bump major`, `update`, or `fix`. Every push must contain exactly one valid version transition.
6. Run `pnpm test`, `pnpm run build`, and `pnpm audit` before opening a pull request.
7. Explain any new subprocess, filesystem, clipboard, network, or environment access in the pull request and README.

By submitting a contribution, you agree that it may be distributed under the repository's MIT License.
