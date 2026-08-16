#!/bin/sh
# Build a signed release APK and put it somewhere obvious, with a name that
# says which build it is.
#
# WHY THIS EXISTS. The README used to give three export lines and a build
# command, and following them exactly failed: the block had no `cd`, so it ran
# in whatever directory you happened to be in and Flutter answered "No
# pubspec.yaml file found". Worse, the README claimed Flutter was "already
# configured to find the SDK" — it was, but only inside the editor's sandbox,
# whose XDG_CONFIG_HOME points at a Flatpak directory. A normal terminal reads
# ~/.config/flutter/settings and found nothing there.
#
# Run from anywhere:
#     sh ~/ports_ahoy/tool/build_apk.sh

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$HOME/ports_ahoy_builds"

export PATH="$HOME/flutter/bin:$PATH"

cd "$REPO"

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
echo "Building Ports Ahoy! $VERSION from $REPO"
echo

# Keep the version the app reports in step with pubspec, so a build can never
# misreport itself in a bug report.
dart run tool/stamp_version.dart

flutter build apk --release

APK="$REPO/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK" ]; then
  echo "Build reported success but $APK is missing." >&2
  exit 1
fi

mkdir -p "$OUT"
DEST="$OUT/PortsAhoy-$(echo "$VERSION" | tr '+' '-').apk"
cp "$APK" "$DEST"

echo
echo "APK: $DEST"
echo "size: $(du -h "$DEST" | awk '{print $1}')"

if [ -f "$REPO/android/key.properties" ]; then
  echo "signed with your upload key (android/key.properties present)"
else
  echo "WARNING: android/key.properties missing — this is a DEBUG-signed build"
  echo "and will not update an installed release build."
fi

if command -v adb >/dev/null 2>&1; then
  echo
  echo "To push it to a plugged-in phone:"
  echo "    adb install -r \"$DEST\""
fi
