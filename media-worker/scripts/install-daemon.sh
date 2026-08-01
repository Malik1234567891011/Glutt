#!/usr/bin/env bash
#
# Keep the Supabase claim loop running on this Mac as a LaunchAgent.
#
# Until the worker is hosted somewhere, imports only finish while this is up:
# the app enqueues a job in Postgres and something has to download, cut and
# upload the clips. Without it every import parks at "Preparing technique clips".
#
#   ./scripts/install-daemon.sh            # install + start
#   ./scripts/install-daemon.sh --uninstall
#
# Logs: media-worker/work/daemon.log
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.glutt.mediaworker"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Uninstalled $LABEL"
  exit 0
fi

if [[ ! -f "$ROOT/.env" ]]; then
  echo "Missing $ROOT/.env (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)." >&2
  exit 1
fi

NODE_BIN="$(command -v node)"
# launchd starts with a bare PATH, so ffmpeg/ffprobe must be resolved here.
FFMPEG_BIN="$(command -v ffmpeg)"
FFPROBE_BIN="$(command -v ffprobe)"
mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/work"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE_BIN</string>
    <string>$ROOT/scripts/claimSupabaseJobs.js</string>
    <string>--loop</string>
    <string>--interval=30</string>
  </array>
  <key>WorkingDirectory</key><string>$ROOT</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>FFMPEG_BIN</key><string>$FFMPEG_BIN</string>
    <key>FFPROBE_BIN</key><string>$FFPROBE_BIN</string>
    <key>WORKER_ID</key><string>launchd-$(hostname -s)</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$ROOT/work/daemon.log</string>
  <key>StandardErrorPath</key><string>$ROOT/work/daemon.log</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
echo "  status: launchctl print gui/$(id -u)/$LABEL | head -20"
echo "  logs:   tail -f $ROOT/work/daemon.log"
echo "  stop:   $0 --uninstall"
