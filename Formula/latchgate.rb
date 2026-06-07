# frozen_string_literal: true

# Homebrew formula for LatchGate — execution security kernel for AI agents.
#
# Installs two binaries:
#
#   latchgate   Server, CLI, and operator tooling.
#   latch-mcp   MCP adapter — bridges IDE agents (Cursor, Claude Desktop,
#               Cline, Windsurf, Codex CLI) to a running gate instance.
#
# Every tool call an agent makes is authenticated, policy-evaluated,
# sandboxed in WASM, and produces a signed audit receipt.
#
# Install:  brew install latchgate-ai/tap/latchgate
# Upgrade:  brew upgrade latchgate
# Docs:     https://latchgate-docs.pages.dev
#
# Maintainer notes:
#   Checksums are updated by scripts/update-formula.sh after each release.
#   The binaries are built and published by the latchgate-ai/latchgate CI
#   pipeline (GitHub Actions) for 4 targets. Action manifests, WASM
#   providers, and OPA policies are compiled into the binary at build
#   time — the share/ resources in the tarball are not installed.

class Latchgate < Formula
  desc "Execution security kernel for AI agents"
  homepage "https://github.com/latchgate-ai/latchgate"
  version "0.1.4"
  license "Apache-2.0"

  # No source compilation — pre-built binaries only.
  bottle :unneeded

  livecheck do
    url "https://github.com/latchgate-ai/latchgate/releases/latest"
    strategy :github_latest
  end

  # ── Platform-specific binaries ──────────────────────────────────────────

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/latchgate-ai/latchgate/releases/download/v#{version}/latchgate-v#{version}-aarch64-apple-darwin.tar.gz"
      sha256 "2ecae0cb0a8e62b7b30667f1ca742feddca2f2bdf8c0686610413ad276090493"
    else
      url "https://github.com/latchgate-ai/latchgate/releases/download/v#{version}/latchgate-v#{version}-x86_64-apple-darwin.tar.gz"
      sha256 "76d116fe3c752178d29c6fa8affdb6a90011f1dd72ce1c63a6137001dafba476"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/latchgate-ai/latchgate/releases/download/v#{version}/latchgate-v#{version}-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "4b7790779f0509287924576b808bb9543b1b442688347c22540dcde0fe6c2292"
    else
      url "https://github.com/latchgate-ai/latchgate/releases/download/v#{version}/latchgate-v#{version}-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "0f2f973391c0781becb0e6ddd1be04aaa9133d2992d4fc5fea1e2fbf12edb858"
    end
  end

  def install
    bin.install "latchgate"
    bin.install "latch-mcp"
  end

  def caveats
    <<~EOS
      Quick start:
        1. Initialise a project:
             latchgate init

        2. Start the gate:
             latchgate up

        3. Configure your IDE:
             latch-mcp install --ide cursor    # or: claude, cline, windsurf, codex

        4. Restart your IDE — every tool call now goes through LatchGate.

      Documentation: https://latchgate-docs.pages.dev
    EOS
  end

  test do
    # ── latchgate ────────────────────────────────────────────────────────

    assert_match version.to_s, shell_output("#{bin}/latchgate --version")

    help_output = shell_output("#{bin}/latchgate --help")
    assert_match "up", help_output
    assert_match "serve", help_output
    assert_match "init", help_output
    assert_match "doctor", help_output

    # init --list-presets works without a running gate or config file.
    presets_output = shell_output("#{bin}/latchgate init --list-presets")
    assert_match "coding-assistant", presets_output

    # Shell completions generate without error.
    bash_completions = shell_output("#{bin}/latchgate completions bash")
    assert_match "latchgate", bash_completions

    # ── latch-mcp ────────────────────────────────────────────────────────

    assert_match version.to_s, shell_output("#{bin}/latch-mcp --version")

    mcp_help = shell_output("#{bin}/latch-mcp --help")
    assert_match "serve", mcp_help
    assert_match "install", mcp_help

    # Verify --dry-run for each JSON-based IDE produces valid JSON
    # containing the latchgate server entry.
    %w[cursor claude cline windsurf].each do |ide|
      output = shell_output("#{bin}/latch-mcp install --ide #{ide} --dry-run 2>&1")
      assert_match "latchgate", output

      # The JSON snippet is written to stdout; stderr has the dry-run
      # banner. Extract stdout-only content and verify it parses.
      json_output = shell_output("#{bin}/latch-mcp install --ide #{ide} --dry-run")
      require "json"
      JSON.parse(json_output)
    end

    # Codex uses TOML — verify the snippet contains the server entry.
    codex_output = shell_output("#{bin}/latch-mcp install --ide codex --dry-run")
    assert_match "mcp_servers.latchgate", codex_output
  end
end
