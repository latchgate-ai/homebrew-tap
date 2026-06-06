# latchgate-ai/homebrew-tap

Homebrew formulae for [latchgate-ai](https://github.com/latchgate-ai) projects.

## Install

```bash
brew install latchgate-ai/tap/latchgate
```

## Formulae

| Formula | Description |
|---|---|
| [`latchgate`](Formula/latchgate.rb) | Execution security kernel for AI agents |

## Quick start

```bash
latchgate init
latchgate up
latch-mcp install --ide cursor    # or: claude, cline, windsurf, codex
```

Restart your IDE — every tool call now goes through LatchGate.

See the [LatchGate documentation](https://latchgate-docs.pages.dev) for full setup instructions.

## Updating

Formulae are updated after each LatchGate release. To upgrade:

```bash
brew update && brew upgrade latchgate
```

### Maintainer: update checksums after a release

```bash
./scripts/update-formula.sh          # latest release
./scripts/update-formula.sh 0.2.0    # specific version
```

Requires `gh` (GitHub CLI) for build provenance verification.

## License

Apache-2.0. See [LICENSE](LICENSE).
