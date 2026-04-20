#!/usr/bin/env bash
# ============================================================================
# Caldwell SYSPRO MCP Server — Linux / macOS Updater
# ============================================================================
# In-place update of an existing install. Detects the install directory from
# the location of this script, downloads the matching platform tarball, and
# replaces the binary while preserving user files (connections.json,
# key-entities.custom.json, appsettings.json, playbooks/).
#
# Usage:
#   ./update.sh                       # update from latest stable
#   ./update.sh --channel beta        # update from latest beta
#   ./update.sh --platform osx-x64    # force a specific platform asset
# ============================================================================

set -euo pipefail

CHANNEL="latest"
PLATFORM_OVERRIDE=""
REPO="mepapps/caldwell-syspro-mcp-releases"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALL_DIR="$SCRIPT_DIR"

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
            echo "Usage: update.sh [--channel latest|beta] [--install-dir /path] [--platform linux-x64|osx-arm64|osx-x64]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

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
            exit 1
            ;;
    esac
}

if [[ -n "$PLATFORM_OVERRIDE" ]]; then
    PLATFORM="$PLATFORM_OVERRIDE"
else
    PLATFORM="$(detect_platform)"
fi

EXE_NAME="Caldwell.Syspro.Mcp.Server"
EXE_PATH="${INSTALL_DIR}/${EXE_NAME}"

echo ""
echo "  ============================================================"
echo "   Caldwell SYSPRO MCP Server — Update"
echo "  ============================================================"
echo ""
echo "  Platform:    ${PLATFORM}"
echo "  Channel:     ${CHANNEL}"
echo "  Install dir: ${INSTALL_DIR}"
echo ""

for cmd in curl jq tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  [ERROR] Required command '${cmd}' not found."
        exit 1
    fi
done

# ── Find the right release ──────────────────────────────────────────
echo "  Checking for latest ${CHANNEL} release..."

if [[ "$CHANNEL" == "latest" ]]; then
    RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        -H "Accept: application/vnd.github+json" 2>/dev/null) || {
        echo "  [ERROR] Could not fetch latest release."
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
        echo "  [ERROR] No beta releases found."
        exit 1
    fi
fi

TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
echo "  Latest version: ${TAG}"

ASSET_PATTERN="${PLATFORM}\\.tar\\.gz$"
DOWNLOAD_URL=$(echo "$RELEASE_JSON" \
    | jq -r --arg pat "$ASSET_PATTERN" '.assets[] | select(.name | test($pat)) | .browser_download_url' \
    | head -1)

if [[ -z "$DOWNLOAD_URL" ]] || [[ "$DOWNLOAD_URL" == "null" ]]; then
    echo "  [ERROR] No ${PLATFORM} tar.gz asset found in release ${TAG}."
    exit 1
fi

ASSET_NAME=$(basename "$DOWNLOAD_URL")
echo "  Downloading: ${ASSET_NAME}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_TARBALL="${TEMP_DIR}/${ASSET_NAME}"
TEMP_EXTRACT="${TEMP_DIR}/extract"
mkdir -p "$TEMP_EXTRACT"

curl -fsSL -o "$TEMP_TARBALL" "$DOWNLOAD_URL" || {
    echo "  [ERROR] Download failed."
    exit 1
}

echo "  Extracting..."
tar -xzf "$TEMP_TARBALL" -C "$TEMP_EXTRACT"

if [[ ! -f "${TEMP_EXTRACT}/${EXE_NAME}" ]]; then
    echo "  [ERROR] ${EXE_NAME} not found in the downloaded package."
    exit 1
fi

# ── Stop running server processes (best effort) ────────────────────
# The MCP client will auto-relaunch the server on the next tool call.
if pgrep -f "${EXE_NAME}" >/dev/null 2>&1; then
    echo "  Stopping running MCP server instances..."
    pkill -f "${EXE_NAME}" 2>/dev/null || true
    sleep 1
fi

# ── Backup user files ──────────────────────────────────────────────
BACKUP_DIR="${TEMP_DIR}/backup"
mkdir -p "$BACKUP_DIR"
for f in connections.json key-entities.custom.json appsettings.json; do
    if [[ -f "${INSTALL_DIR}/${f}" ]]; then
        cp "${INSTALL_DIR}/${f}" "${BACKUP_DIR}/${f}"
    fi
done
if [[ -d "${INSTALL_DIR}/playbooks" ]]; then
    cp -R "${INSTALL_DIR}/playbooks" "${BACKUP_DIR}/playbooks"
fi

# ── Copy new files in place ───────────────────────────────────────
echo "  Installing update..."
mkdir -p "$INSTALL_DIR"
# cp -R src/. dest/ copies contents of src into dest, overwriting matching files
cp -R "${TEMP_EXTRACT}/." "${INSTALL_DIR}/"

chmod +x "${EXE_PATH}" 2>/dev/null || true
for s in install.sh update.sh diagnose-syspro.sh; do
    if [[ -f "${INSTALL_DIR}/${s}" ]]; then
        chmod +x "${INSTALL_DIR}/${s}"
    fi
done

# macOS: clear quarantine attribute on the freshly-extracted binary
if [[ "$PLATFORM" == osx-* ]] && command -v xattr &>/dev/null; then
    xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
fi

# ── Restore user files ────────────────────────────────────────────
for f in connections.json key-entities.custom.json appsettings.json; do
    if [[ -f "${BACKUP_DIR}/${f}" ]]; then
        cp "${BACKUP_DIR}/${f}" "${INSTALL_DIR}/${f}"
        echo "  [OK] Preserved ${f}"
    fi
done
if [[ -d "${BACKUP_DIR}/playbooks" ]]; then
    cp -R "${BACKUP_DIR}/playbooks/." "${INSTALL_DIR}/playbooks/"
    echo "  [OK] Preserved playbooks/"
fi

echo ""
echo "  ============================================================"
echo "   UPDATE COMPLETE — ${TAG} (${PLATFORM})"
echo "  ============================================================"
echo ""
echo "  Restart your MCP client to use the new version."
echo ""
