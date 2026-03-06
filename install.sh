#!/bin/sh
set -e

REPO="dzmbs/regatta"

OS=$(uname -s)
case "$OS" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) arch="x64" ;;
  arm64|aarch64) arch="arm64" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

BINARY="regatta-${os}-${arch}"
URL="https://github.com/${REPO}/releases/latest/download/${BINARY}"

echo "Installing regatta (${os}/${arch})..."
curl -fsSL -o regatta "$URL"
chmod +x regatta

if [ -w "/usr/local/bin" ]; then
  mv regatta /usr/local/bin/regatta
  echo "Installed to /usr/local/bin/regatta"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo mv regatta /usr/local/bin/regatta
  echo "Installed to /usr/local/bin/regatta"
else
  mkdir -p "$HOME/.local/bin"
  mv regatta "$HOME/.local/bin/regatta"
  echo "Installed to $HOME/.local/bin/regatta"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
fi

regatta version
