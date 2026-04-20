#!/usr/bin/env bash
# ============================================================================
# Caldwell SYSPRO MCP Server — Linux / macOS Installer
# ============================================================================
# One-liner install:
#   curl -fsSL https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.sh | bash
#
# Auto-detects platform:
#   - Linux x86_64        → linux-x64
#   - macOS Apple Silicon → osx-arm64
#   - macOS Intel         → osx-x64
#
# Options:
#   --channel beta          Install beta channel (default: latest)
#   --install-dir /path     Custom install directory
#   --platform <id>         Override platform detection (linux-x64|osx-arm64|osx-x64)
#
# Examples:
#   curl -fsSL .../install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --channel beta
#   curl -fsSL .../install.sh | bash -s -- --install-dir /opt/caldwell-mcp
#   curl -fsSL .../install.sh | bash -s -- --platform osx-x64    # force Intel build on M1 (Rosetta 2)
# ============================================================================

set -euo pipefail

CHANNEL="latest"
INSTALL_DIR=""
PLATFORM_OVERRIDE=""
REPO="mepapps/caldwell-syspro-mcp-releases"

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel)
            CHANNEL="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --platform)
            PLATFORM_OVERRIDE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: install.sh [--channel latest|beta] [--install-dir /path] [--platform linux-x64|osx-arm64|osx-x64]"
            echo ""
            echo "Options:"
            echo "  --channel      Release channel: 'latest' (default) or 'beta'"
            echo "  --install-dir  Installation directory (default: ~/.local/share/caldwell-syspro-mcp)"
            echo "  --platform     Override auto-detected platform"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ── Detect platform ─────────────────────────────────────────────────
detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Linux)
            case "$arch" in
                x86_64|amd64) echo "linux-x64" ;;
                *) echo "  [ERROR] Unsupported Linux architecture: $arch" >&2; exit 1 ;;
            esac
            ;;
        Darwin)
            case "$arch" in
                arm64|aarch64) echo "osx-arm64" ;;
                x86_64) echo "osx-x64" ;;
                *) echo "  [ERROR] Unsupported macOS architecture: $arch" >&2; exit 1 ;;
            esac
            ;;
        *)
            echo "  [ERROR] Unsupported OS: $os" >&2
            echo "  This installer supports Linux and macOS. Use install.ps1 on Windows." >&2
            exit 1
            ;;
    esac
}

if [[ -n "$PLATFORM_OVERRIDE" ]]; then
    PLATFORM="$PLATFORM_OVERRIDE"
else
    PLATFORM="$(detect_platform)"
fi

case "$PLATFORM" in
    linux-x64|osx-arm64|osx-x64) ;;
    *)
        echo "  [ERROR] Unknown --platform: $PLATFORM"
        echo "  Valid: linux-x64, osx-arm64, osx-x64"
        exit 1
        ;;
esac

# Default install dir per platform
if [[ -z "$INSTALL_DIR" ]]; then
    case "$PLATFORM" in
        osx-*)  INSTALL_DIR="${HOME}/Library/Application Support/caldwell-syspro-mcp" ;;
        *)      INSTALL_DIR="${HOME}/.local/share/caldwell-syspro-mcp" ;;
    esac
fi

echo ""
echo "  ============================================================"
echo "   Caldwell SYSPRO MCP Server — Installer"
echo "  ============================================================"
echo ""
echo "  Platform:   ${PLATFORM}"
echo "  Channel:    ${CHANNEL}"
echo "  Install to: ${INSTALL_DIR}"
echo ""

# ── Check dependencies ──────────────────────────────────────────────
for cmd in curl jq tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  [ERROR] Required command '${cmd}' not found. Install it and try again."
        if [[ "$PLATFORM" == osx-* ]]; then
            echo "         On macOS:  brew install ${cmd}"
        fi
        exit 1
    fi
done

# ── Find the right release ──────────────────────────────────────────
echo "  Finding latest ${CHANNEL} release..."

if [[ "$CHANNEL" == "latest" ]]; then
    RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        -H "Accept: application/vnd.github+json" 2>/dev/null) || {
        echo "  [ERROR] Could not fetch latest release."
        echo "  Visit https://github.com/${REPO}/releases to download manually."
        exit 1
    }
else
    RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" \
        -H "Accept: application/vnd.github+json" 2>/dev/null \
        | jq '[.[] | select(.prerelease == true)] | first') || {
        echo "  [ERROR] Could not fetch beta releases."
        exit 1
    }
    if [[ "$RELEASE_JSON" == "null" ]] || [[ -z "$RELEASE_JSON" ]]; then
        echo "  [ERROR] No beta releases found. Use --channel latest for the stable release."
        exit 1
    fi
fi

TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
RELEASE_NAME=$(echo "$RELEASE_JSON" | jq -r '.name')
echo "  Found: ${RELEASE_NAME} (${TAG})"

# ── Find the platform-specific asset ────────────────────────────────
# Asset names look like: caldwell-syspro-mcp-vX.Y.Z-single-<platform>.tar.gz
ASSET_PATTERN="${PLATFORM}\\.tar\\.gz$"
DOWNLOAD_URL=$(echo "$RELEASE_JSON" \
    | jq -r --arg pat "$ASSET_PATTERN" '.assets[] | select(.name | test($pat)) | .browser_download_url' \
    | head -1)

if [[ -z "$DOWNLOAD_URL" ]] || [[ "$DOWNLOAD_URL" == "null" ]]; then
    echo "  [ERROR] No ${PLATFORM} tar.gz asset found in release ${TAG}."
    if [[ "$PLATFORM" == "osx-arm64" ]]; then
        echo "  This release may predate macOS Apple Silicon support."
        echo "  You can try the Intel build under Rosetta 2:"
        echo "      curl -fsSL .../install.sh | bash -s -- --platform osx-x64"
    elif [[ "$PLATFORM" == "osx-x64" ]]; then
        echo "  This release may predate macOS support."
    else
        echo "  This release may predate ${PLATFORM} support."
    fi
    echo "  Visit https://github.com/${REPO}/releases/tag/${TAG} to check available downloads."
    exit 1
fi

ASSET_NAME=$(basename "$DOWNLOAD_URL")
echo "  Downloading: ${ASSET_NAME}"

# ── Download ────────────────────────────────────────────────────────
TEMP_DIR=$(mktemp -d)
TEMP_TARBALL="${TEMP_DIR}/${ASSET_NAME}"

curl -fsSL -o "$TEMP_TARBALL" "$DOWNLOAD_URL" || {
    echo "  [ERROR] Download failed."
    rm -rf "$TEMP_DIR"
    exit 1
}

# du -m differs slightly on macOS vs Linux but both work for an approximate MB size
SIZE_MB=$(du -m "$TEMP_TARBALL" | cut -f1)
echo "  [OK] Downloaded (${SIZE_MB} MB)"

# ── Backup user files ───────────────────────────────────────────────
BACKUP_DIR="${TEMP_DIR}/backup"
mkdir -p "$BACKUP_DIR"

for f in connections.json key-entities.custom.json appsettings.json; do
    if [[ -f "${INSTALL_DIR}/${f}" ]]; then
        cp "${INSTALL_DIR}/${f}" "${BACKUP_DIR}/${f}"
        echo "  [OK] Backed up ${f}"
    fi
done

# Also preserve playbooks directory (user may have added custom ones)
if [[ -d "${INSTALL_DIR}/playbooks" ]]; then
    cp -R "${INSTALL_DIR}/playbooks" "${BACKUP_DIR}/playbooks"
    echo "  [OK] Backed up playbooks/"
fi

# ── Extract ─────────────────────────────────────────────────────────
echo "  Extracting..."

mkdir -p "$INSTALL_DIR"
tar -xzf "$TEMP_TARBALL" -C "$INSTALL_DIR"

# Make the binary executable
EXE_PATH="${INSTALL_DIR}/Caldwell.Syspro.Mcp.Server"
if [[ -f "$EXE_PATH" ]]; then
    chmod +x "$EXE_PATH"
fi

# Make shell scripts executable too
for s in install.sh update.sh diagnose-syspro.sh; do
    if [[ -f "${INSTALL_DIR}/${s}" ]]; then
        chmod +x "${INSTALL_DIR}/${s}"
    fi
done

# ── macOS: clear quarantine attribute so Gatekeeper doesn't block ──
if [[ "$PLATFORM" == osx-* ]] && command -v xattr &>/dev/null; then
    # Strip com.apple.quarantine from the binary and any bundled libs.
    # Without this, the first launch after curl|bash triggers a
    # "cannot be opened because the developer cannot be verified" prompt.
    xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
fi

echo "  [OK] Installed to ${INSTALL_DIR}"

# ── Restore user files ──────────────────────────────────────────────
for f in connections.json key-entities.custom.json appsettings.json; do
    if [[ -f "${BACKUP_DIR}/${f}" ]]; then
        cp "${BACKUP_DIR}/${f}" "${INSTALL_DIR}/${f}"
        echo "  [OK] Restored ${f}"
    fi
done

if [[ -d "${BACKUP_DIR}/playbooks" ]]; then
    # Copy the user's playbooks back, preserving any new shipped ones that don't conflict
    cp -R "${BACKUP_DIR}/playbooks/." "${INSTALL_DIR}/playbooks/"
    echo "  [OK] Restored playbooks/"
fi

# ── First-time setup ───────────────────────────────────────────────
CONNECTIONS_PATH="${INSTALL_DIR}/connections.json"
SAMPLE_PATH="${INSTALL_DIR}/connections.sample.json"

if [[ ! -f "$CONNECTIONS_PATH" ]] && [[ -f "$SAMPLE_PATH" ]]; then
    cp "$SAMPLE_PATH" "$CONNECTIONS_PATH"
    echo "  [OK] Created connections.json from sample"
fi

# ── Cleanup ─────────────────────────────────────────────────────────
rm -rf "$TEMP_DIR"

# ── Done ────────────────────────────────────────────────────────────
echo ""
echo "  ============================================================"
echo "   INSTALLED SUCCESSFULLY — ${TAG} (${PLATFORM})"
echo "  ============================================================"
echo ""
echo "  Location: ${INSTALL_DIR}"
echo "  Binary:   ${EXE_PATH}"
echo ""
echo "  NEXT STEPS:"
echo ""
echo "  1. Open http://localhost:5199 to add database connections"
echo "     (starts automatically when an MCP client connects)"
echo ""
echo "  2. Add to your MCP client config:"
echo ""
echo "     Claude Code (~/.claude.json):"
echo "     {"
echo "       \"mcpServers\": {"
echo "         \"caldwell-syspro\": {"
echo "           \"command\": \"${EXE_PATH}\""
echo "         }"
echo "       }"
echo "     }"
echo ""
echo "     Cursor (~/.cursor/mcp.json):"
echo "     {"
echo "       \"mcpServers\": {"
echo "         \"caldwell-syspro\": {"
echo "           \"command\": \"${EXE_PATH}\""
echo "         }"
echo "       }"
echo "     }"
echo ""
if [[ "$PLATFORM" == osx-* ]]; then
echo "     Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json):"
echo "     {"
echo "       \"mcpServers\": {"
echo "         \"caldwell-syspro\": {"
echo "           \"command\": \"${EXE_PATH}\""
echo "         }"
echo "       }"
echo "     }"
echo ""
fi
echo "  3. Restart your MCP client"
echo ""
echo "  To update later, re-run this install command, or run:"
echo "      \"${INSTALL_DIR}/update.sh\""
echo ""
