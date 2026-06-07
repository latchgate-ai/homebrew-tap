#!/usr/bin/env bash
# Update Formula/latchgate.rb with real SHA-256 checksums from a GitHub Release.
#
# Usage:
#   ./scripts/update-formula.sh              # uses latest release
#   ./scripts/update-formula.sh 0.2.0        # uses specific version
#
# Prerequisites: curl, shasum (or sha256sum), jq, gh (GitHub CLI)
#
# What it does:
#   1. Resolves the target version (argument or latest GitHub release tag).
#   2. Checks if the formula is already at the target version (idempotency).
#   3. Downloads all 4 platform tarballs to a temp directory.
#   4. Verifies build provenance attestation for each tarball.
#   5. Computes SHA-256 for each.
#   6. Rewrites the formula in-place with the new version and checksums.
#   7. Runs `brew audit` if available.

set -euo pipefail

REPO="latchgate-ai/latchgate"
FORMULA="Formula/latchgate.rb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMULA_PATH="$REPO_ROOT/$FORMULA"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${BOLD}%s${RESET}\n" "$*"; }
ok()    { printf "${GREEN}✓${RESET} %s\n" "$*"; }
fail()  { printf "${RED}✗ %s${RESET}\n" "$*" >&2; exit 1; }

# ── Prerequisite checks ──────────────────────────────────────────────────

command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v gh >/dev/null 2>&1   || fail "gh (GitHub CLI) is required for attestation verification. Install: https://cli.github.com"

# Check whether `gh attestation` is available (requires gh ≥ 2.49.0).
CAN_ATTEST=true
if ! gh attestation --help >/dev/null 2>&1; then
    CAN_ATTEST=false
    printf "${RED}⚠${RESET}  gh attestation not supported (gh ≥ 2.49.0 required). "
    printf "Attestation verification will be ${BOLD}skipped${RESET}.\n"
    printf "   Upgrade: ${BOLD}brew upgrade gh${RESET}  or  ${BOLD}https://cli.github.com${RESET}\n\n"
fi

# ── Resolve version ──────────────────────────────────────────────────────

if [ -n "${1:-}" ]; then
    VERSION="$1"
    info "Using specified version: v${VERSION}"
else
    command -v jq >/dev/null 2>&1 || fail "jq is required to resolve the latest release. Install it or pass a version argument."
    info "Resolving latest release..."
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    [ "$VERSION" != "null" ] && [ -n "$VERSION" ] || fail "Could not resolve latest release from GitHub API."
    ok "Latest release: v${VERSION}"
fi

# ── Validate formula exists ──────────────────────────────────────────────

[ -f "$FORMULA_PATH" ] || fail "Formula not found at $FORMULA_PATH — run from the repo root."

# ── Idempotency check ────────────────────────────────────────────────────

CURRENT_VERSION=$(sed -n 's/^[[:space:]]*version "\([^"]*\)"/\1/p' "$FORMULA_PATH")
if [ "$CURRENT_VERSION" = "$VERSION" ] && ! grep -q "PLACEHOLDER_" "$FORMULA_PATH"; then
    ok "Formula already at v${VERSION} with all checksums — nothing to do."
    exit 0
fi

# ── Download, verify, and checksum ───────────────────────────────────────

TARGETS=(
    "aarch64-apple-darwin"
    "x86_64-apple-darwin"
    "aarch64-unknown-linux-gnu"
    "x86_64-unknown-linux-gnu"
)

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Detect sha command.
if command -v sha256sum >/dev/null 2>&1; then
    sha_cmd() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
    sha_cmd() { shasum -a 256 "$1" | awk '{print $1}'; }
else
    fail "Neither sha256sum nor shasum found."
fi

declare -A SHAS

for target in "${TARGETS[@]}"; do
    filename="latchgate-v${VERSION}-${target}.tar.gz"
    url="https://github.com/${REPO}/releases/download/v${VERSION}/${filename}"
    dest="$TMPDIR/$filename"

    info "Downloading ${filename}..."
    if ! curl -fsSL -o "$dest" "$url"; then
        fail "Download failed: $url — does the release asset exist?"
    fi

    if [ "$CAN_ATTEST" = true ]; then
        info "Verifying attestation for ${filename}..."
        if ! gh attestation verify "$dest" --repo "${REPO}" 2>&1; then
            fail "Attestation verification failed for ${filename}. The artifact may have been tampered with."
        fi
        ok "Attestation verified: ${target}"
    fi

    sha=$(sha_cmd "$dest")
    SHAS[$target]="$sha"
    ok "$target: $sha"
done

# ── Rewrite formula ──────────────────────────────────────────────────────

info "Updating $FORMULA..."

# We use a targeted sed approach: replace the version line and each
# placeholder/SHA line. This is more robust than a full-file rewrite
# because it preserves any manual edits to comments or structure.

# Update version.
sed -i.bak "s/^  version \".*\"/  version \"${VERSION}\"/" "$FORMULA_PATH"

# Update each SHA. Match any 64-char hex string or PLACEHOLDER_* token.
for target in "${TARGETS[@]}"; do
    # Convert target to the placeholder constant name (uppercase, underscores).
    placeholder=$(echo "$target" | tr '[:lower:]-' '[:upper:]_')
    sha="${SHAS[$target]}"

    # Match either a PLACEHOLDER_* token or an existing 64-char hex SHA.
    sed -i.bak "/${target}/{ n; s/sha256 \"[A-Fa-f0-9_]\{64,\}\"/sha256 \"${sha}\"/; s/sha256 \"PLACEHOLDER_${placeholder}\"/sha256 \"${sha}\"/; }" "$FORMULA_PATH"
done

# Also update the URL version fragments.
sed -i.bak "s|/releases/download/v[0-9][0-9.]*|/releases/download/v${VERSION}|g" "$FORMULA_PATH"
sed -i.bak "s|latchgate-v[0-9][0-9.]*-|latchgate-v${VERSION}-|g" "$FORMULA_PATH"

rm -f "${FORMULA_PATH}.bak"

ok "Formula updated to v${VERSION}"

# ── Verify ───────────────────────────────────────────────────────────────

# Quick sanity check: no PLACEHOLDER_ tokens should remain.
if grep -q "PLACEHOLDER_" "$FORMULA_PATH"; then
    fail "Formula still contains PLACEHOLDER_ tokens — manual fix required."
fi

# Count SHAs (should be exactly 4 distinct sha256 lines with 64-char hex).
SHA_COUNT=$(grep -c 'sha256 "[a-f0-9]\{64\}"' "$FORMULA_PATH" || true)
if [ "$SHA_COUNT" -ne 4 ]; then
    fail "Expected 4 SHA-256 entries, found ${SHA_COUNT} — review $FORMULA_PATH manually."
fi

ok "All 4 checksums present"

# ── Optional: brew audit ─────────────────────────────────────────────────

if command -v brew >/dev/null 2>&1; then
    info "Running brew audit..."
    if brew audit --formula latchgate 2>&1; then
        ok "brew audit passed"
    else
        # Non-fatal: audit may fail on CI without a full Homebrew install.
        printf "${RED}brew audit reported issues (see above)${RESET}\n"
    fi
fi

# ── Done ─────────────────────────────────────────────────────────────────

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " Formula updated: latchgate ${VERSION}"
info ""
info " Next steps:"
info "   git diff $FORMULA"
info "   git add $FORMULA && git commit -m 'latchgate ${VERSION}'"
info "   git push"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
