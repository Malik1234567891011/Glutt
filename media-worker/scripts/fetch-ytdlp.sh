#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/bin"
OS="$(uname -s)"
case "$OS" in
  Darwin) URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" ;;
  Linux)  URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux" ;;
  *) echo "unsupported OS: $OS"; exit 1 ;;
esac
curl -L -o "$ROOT/bin/yt-dlp" "$URL"
chmod +x "$ROOT/bin/yt-dlp"
"$ROOT/bin/yt-dlp" --version
echo "Installed $ROOT/bin/yt-dlp"
