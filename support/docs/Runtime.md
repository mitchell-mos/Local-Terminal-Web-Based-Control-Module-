# Bundled runtime provenance

Release builds of `Control Module.app` may bundle an unmodified Node.js executable so the app can run without Codex, ChatGPT, another LLM, or a system Node.js installation.

The currently verified macOS Apple silicon bundle uses:

- Node.js: `v24.17.0` (official `darwin-arm64` distribution)
- Archive: `node-v24.17.0-darwin-arm64.tar.xz`
- SHA-256: `cf7e9152d7bd86c140f6eccf3577abfbaf8960be1ca49d9d900e8484984dcb9a`
- Download: `https://nodejs.org/download/release/v24.17.0/node-v24.17.0-darwin-arm64.tar.xz`
- Checksums: `https://nodejs.org/download/release/v24.17.0/SHASUMS256.txt`

The Control Module, Setup, and Uninstall app launchers are built as ARM64-only executables with native execution required. Intel Macs and Rosetta translation are intentionally unsupported.

Setup downloads this archive directly from nodejs.org, checks the pinned SHA-256 value before extraction, and caches it only in Control Module’s private Application Support folder. The app bundle retains the complete runtime and the release's Node.js `LICENSE` file at `Contents/Resources/runtime/LICENSE-node.txt`. The runtime is not stored in this source repository.
