#!/usr/bin/env bash
# ============================================================================
# Caldwell SYSPRO MCP Server — Linux Installer
# ============================================================================
# One-liner install:
#   curl -fsSL https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.sh | bash
#
# Options:
#   --channel beta          Install beta channel (default: latest)
#   --install-dir /path     Custom install directory
#
# Examples:
#   curl -fsSL .../install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --channel beta
#   curl -fsSL .../install.sh | bash -s -- --install-dir /opt/caldwell-mcp
# ============================================================================

set -euo pipefail

CHANNEL="latest"
INSTALL_DIR="${HOME}/.local/share/caldwell-syspro-mcp"
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
        --help|-h)
            echo "Usage: install.sh [--channel latest|beta] [--install-dir /path]"
            echo ""
            echo "Options:"
            echo "  --channel      Release channel: 'latest' (default) or 'beta'"
            echo "  --install-dir  Installation directory (default: ~/.local/share/caldwell-syspro-mcp)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "  ============================================================"
echo "   Caldwell SYSPRO MCP Server — Linux Installer"
echo "  ============================================================"
echo ""
echo "  Channel:    ${CHANNEL}"
echo "  Install to: ${INSTALL_DIR}"
echo ""

# ── Check dependencies ──────────────────────────────────────────────
for cmd in curl jq tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  [ERROR] Required command '${cmd}' not found. Install it and try again."
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

# ── Find the linux-x64 asset ────────────────────────────────────────
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | test("linux-x64.*\\.tar\\.gz$")) | .browser_download_url' | head -1)

if [[ -z "$DOWNLOAD_URL" ]] || [[ "$DOWNLOAD_URL" == "null" ]]; then
    echo "  [ERROR] No linux-x64 tar.gz asset found in release ${TAG}."
    echo "  This release may predate Linux support."
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

SIZE_MB=$(du -m "$TEMP_TARBALL" | cut -f1)
echo "  [OK] Downloaded (${SIZE_MB} MB)"

# ── Backup user files ───────────────────────────────────────────────
BACKUP_DIR="${TEMP_DIR}/backup"
mkdir -p "$BACKUP_DIR"

for f in connections.json key-entities.custom.json; do
    if [[ -f "${INSTALL_DIR}/${f}" ]]; then
        cp "${INSTALL_DIR}/${f}" "${BACKUP_DIR}/${f}"
        echo "  [OK] Backed up ${f}"
    fi
done

# Also preserve playbooks directory
if [[ -d "${INSTALL_DIR}/playbooks" ]]; then
    cp -r "${INSTALL_DIR}/playbooks" "${BACKUP_DIR}/playbooks"
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

echo "  [OK] Installed to ${INSTALL_DIR}"

# ── Restore user files ──────────────────────────────────────────────
for f in connections.json key-entities.custom.json; do
    if [[ -f "${BACKUP_DIR}/${f}" ]]; then
        cp "${BACKUP_DIR}/${f}" "${INSTALL_DIR}/${f}"
        echo "  [OK] Restored ${f}"
    fi
done

if [[ -d "${BACKUP_DIR}/playbooks" ]]; then
    cp -r "${BACKUP_DIR}/playbooks" "${INSTALL_DIR}/playbooks"
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
echo "   INSTALLED SUCCESSFULLY — ${TAG}"
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
echo "  3. Restart your MCP client"
echo ""
echo "  To update later, re-run this install command."
echo ""
