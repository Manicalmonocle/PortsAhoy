#!/bin/sh
# Build the web bundle, stamp it so caches cannot serve it stale, and stage it
# into docs/ for GitHub Pages.
#
# WHY THE CACHE-BUST. GitHub Pages serves everything max-age=600 and the
# service worker self-unregisters, so an open tab or installed PWA kept the old
# main.dart.js for up to ten minutes after every deploy — a tester (or the
# developer) would look at the version line and see the previous build. Here we
# append the build version as a query to the bootstrap and the entrypoint, so a
# new build is a genuinely new URL that no cache can satisfy.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export PATH="$HOME/flutter/bin:$PATH"

VER=$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr '+' '-')
echo "Building web for $VER"
flutter build web --release >/dev/null

BOOT=build/web/flutter_bootstrap.js
IDX=build/web/index.html
# main.dart.js, loaded by the bootstrap.
sed -i "s|m(\"main.dart.js\")|m(\"main.dart.js?v=$VER\")|g" "$BOOT"
# the bootstrap itself, loaded by index.html.
sed -i "s|flutter_bootstrap.js\" async|flutter_bootstrap.js?v=$VER\" async|g" "$IDX"
sed -i 's|<base href="/">|<base href="./">|' "$IDX"

# Preserve the downloads that live under docs/dl across the rebuild.
mkdir -p /tmp/pa_dl && cp -f docs/dl/* /tmp/pa_dl/ 2>/dev/null || true
rm -rf docs && cp -r build/web docs
mkdir -p docs/dl && cp -f /tmp/pa_dl/* docs/dl/ 2>/dev/null || true

echo "staged docs/ at $VER"
grep -o "main.dart.js?v=$VER" docs/flutter_bootstrap.js | head -1
grep -o "flutter_bootstrap.js?v=$VER" docs/index.html | head -1
