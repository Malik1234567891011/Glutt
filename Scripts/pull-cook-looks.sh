#!/usr/bin/env bash
# Pull every frame the cook session looked at, with what Chef said about it.
#
# The skills equivalent is pull-skill-looks.sh. This one exists because three
# frames from a real gnocchi cook showed a laptop playing football under
# "confirm the pot is at a rolling boil", a bowl of watermelon under "check pan
# readiness with oil", and a terminal window under "verify gnocchi drained and
# in bowl". Whether she noticed is not knowable from the pictures alone, which
# is why the answers are now written beside them.
#
#   ./scripts/pull-cook-looks.sh [destination]

set -euo pipefail

BUNDLE_ID="com.omarlahmimi.glutt"
DEST="${1:-./cook-looks}"

DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  | sort -u | head -1)

if [ -z "${DEVICE:-}" ]; then
  echo "No device. Plug the phone in and unlock it." >&2
  exit 1
fi

echo "device:      $DEVICE"
echo "destination: $DEST"

rm -rf "$DEST"; mkdir -p "$DEST"

for attempt in 1 2 3; do
  if xcrun devicectl device copy from \
      --device "$DEVICE" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --source Documents/glasses-frames \
      --destination "$DEST" >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" = 3 ] && { echo "Could not read Documents/glasses-frames." >&2; exit 1; }
  sleep 2
done

echo
echo "pulled $(find "$DEST" -name '*.jpg' | wc -l | tr -d ' ') frame(s)"
echo

# The pairing, oldest first, so a cook reads in order.
for img in $(find "$DEST" -name '*.jpg' | sort); do
  answer="${img%.jpg}.txt"
  echo "── $(basename "$img")"
  if [ -f "$answer" ]; then
    sed -n '1,4p' "$answer" | sed 's/^/  /'
  else
    echo "  (no answer recorded, this frame predates the pairing)"
  fi
  echo
done
