#!/bin/bash

set -e

REPO="vutlhari/zenpai"
BINARY_NAME="zenpai"
INSTALL_DIR="/usr/local/bin"

# Detect platform
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case $OS in
    darwin) OS="macos" ;;
    linux) OS="linux" ;;
    *) echo "❌ Unsupported OS: $OS"; exit 1 ;;
esac

case $ARCH in
    x86_64) ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "🔍 Detecting platform: ${OS}-${ARCH}"

# Get latest release
echo "📡 Fetching latest release..."
if command -v rg >/dev/null 2>&1; then
    VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | rg -o '"tag_name":\s*"([^"]+)"' -r '$1')
else
    VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
fi

if [ -z "$VERSION" ]; then
    echo "❌ Failed to get latest version"
    exit 1
fi

echo "📦 Latest version: ${VERSION}"

# Download binary
BINARY_NAME_PLATFORM="${BINARY_NAME}-${OS}-${ARCH}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${BINARY_NAME_PLATFORM}"
TMP_FILE="/tmp/${BINARY_NAME}"

echo "⬇️  Downloading ${BINARY_NAME_PLATFORM}..."
if ! curl -L --fail --silent "${DOWNLOAD_URL}" -o "${TMP_FILE}"; then
    echo "❌ Failed to download from ${DOWNLOAD_URL}"
    echo "💡 Make sure the release exists for your platform"
    exit 1
fi

# Install
chmod +x "${TMP_FILE}"

echo "📁 Installing to ${INSTALL_DIR}/${BINARY_NAME}..."
if [ -w "${INSTALL_DIR}" ]; then
    mv "${TMP_FILE}" "${INSTALL_DIR}/${BINARY_NAME}"
else
    sudo mv "${TMP_FILE}" "${INSTALL_DIR}/${BINARY_NAME}"
fi

# Verify
if command -v ${BINARY_NAME} >/dev/null 2>&1; then
    echo "✅ ${BINARY_NAME} installed successfully!"
    echo "🚀 Run '${BINARY_NAME} --help' to get started"
else
    echo "⚠️  Installation complete but ${INSTALL_DIR} may not be in your PATH"
    echo "💡 Add to PATH: export PATH=\"${INSTALL_DIR}:\$PATH\""
fi
