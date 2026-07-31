# Bundled runtime provenance

Release builds of `Control Module.app` may bundle an unmodified Node.js executable so the app can run without Codex, ChatGPT, another LLM, or a system Node.js installation.

The currently verified macOS Apple silicon bundle uses:

- Node.js: `v24.17.0` (official `darwin-arm64` distribution)
- Archive: `node-v24.17.0-darwin-arm64.tar.xz`
- SHA-256: `cf7e9152d7bd86c140f6eccf3577abfbaf8960be1ca49d9d900e8484984dcb9a`
- Download: `https://nodejs.org/download/release/v24.17.0/node-v24.17.0-darwin-arm64.tar.xz`
- Checksums: `https://nodejs.org/download/release/v24.17.0/SHASUMS256.txt`

The app bundle retains the release's complete Node.js `LICENSE` file at `Contents/Resources/runtime/LICENSE-node.txt`. The binary is not stored in this source repository.
