#!/usr/bin/env bash
# Pull every frame a skill check looked at off the phone, with the verdict it
# produced, so a human (or Claude) can check the model's eyesight against the
# actual pixels.
#
# The argument this exists to settle: Chef reports she cannot see a thumb while
# reporting that she CAN see the fingers wrapped round the handle. From the
# cook's own eyes that is close to impossible. Either the frames really are that
# bad, or she is over-reporting `insufficient`, and a log line saying
# `thumb: insufficient` cannot tell you which.
#
#   ./scripts/pull-skill-looks.sh              # newest device, into ./skill-looks
#   ./scripts/pull-skill-looks.sh ~/somewhere  # somewhere else
#
# Needs a DEBUG build on the device: the archive is compiled out of Release.

set -euo pipefail

BUNDLE_ID="com.omarlahmimi.glutt"
DEST="${1:-./skill-looks}"

# The Identifier column, not the hostname beside it, which carries a
# `.coredevice.local` suffix and is a different thing to type at people.
DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  | sort -u | head -1)

if [ -z "${DEVICE:-}" ]; then
  echo "No device. Plug the phone in and unlock it." >&2
  exit 1
fi

echo "device:      $DEVICE"
echo "destination: $DEST"

rm -rf "$DEST"
mkdir -p "$DEST"

# The connection drops on the first attempt often enough to be worth retrying
# rather than reporting. Same flake as build_run_device.
for attempt in 1 2 3; do
  if xcrun devicectl device copy from \
      --device "$DEVICE" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --source Documents/SkillLooks \
      --destination "$DEST" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    echo "Could not read Documents/SkillLooks." >&2
    echo "Either no check has run yet on this build, or the phone is locked." >&2
    exit 1
  fi
  sleep 2
done

LOOKS=$(find "$DEST" -name "verdict.txt" | wc -l | tr -d ' ')
echo
echo "pulled $LOOKS look(s)"
echo

# The disputed line, per look, up front. Everything else is in the folders.
for verdict in $(find "$DEST" -name "verdict.txt" | sort); do
  folder=$(dirname "$verdict")
  echo "── $(basename "$folder")"
  grep -E "^  (tool|controlPoint|thumb|indexFinger|remainingFingers|wrist|guidingHand)" "$verdict" \
    | sed 's/^/  /' || true
  grep -E "^  (overall|confidence|issue)" "$verdict" | sed 's/^/  /' || true
  echo "  $(ls "$folder"/*.jpg 2>/dev/null | wc -l | tr -d ' ') frame(s): $folder"
  echo
done
