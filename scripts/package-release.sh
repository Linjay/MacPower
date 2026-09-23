#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Keep release packaging separate from the app that may already be running locally.
RELEASE_DIR="$PWD/build/releases"
APP="$RELEASE_DIR/MacPower.app"
mkdir -p "$RELEASE_DIR"
MACPOWER_APP_OUTPUT="$APP" zsh scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(/usr/bin/lipo -archs "$APP/Contents/MacOS/MacPower")
case "$ARCH" in
    arm64|x86_64) ;;
    *) print -u2 "Unexpected binary architectures: $ARCH"; exit 1 ;;
esac
ARCHIVE="MacPower-$VERSION-$ARCH.zip"
# App resources are ordinary bundle files. Do not distribute this Mac's extended
# attributes or AppleDouble metadata alongside the signed app contents.
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$APP" "$RELEASE_DIR/$ARCHIVE"
(
    cd "$RELEASE_DIR"
    /usr/bin/shasum -a 256 "$ARCHIVE" > SHA256SUMS
    /usr/bin/shasum -a 256 -c SHA256SUMS
)
print "Release files: $RELEASE_DIR/$ARCHIVE and SHA256SUMS"
