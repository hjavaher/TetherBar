#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
cd "$(dirname "$0")"
version=$(cat VERSION)
if ! printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
  echo 'VERSION must contain a numeric major.minor.patch version.' >&2
  exit 1
fi
# Refuse symlinked outputs; build only inside this checkout.
for path in build build/TetherBar.app build/TetherBar.app/Contents build/TetherBar.app/Contents/MacOS; do
  if [ -L "$path" ]; then echo "Refusing symlink: $path" >&2; exit 1; fi
done
mkdir -p build
stage=$(mktemp -d "$PWD/build/.compile.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
app="$stage/TetherBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun clang -O2 -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Werror \
  -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
  -framework AppKit -framework CoreWLAN -framework SystemConfiguration \
  -framework ServiceManagement TetherBar.m HBProbe.m -o "$app/Contents/MacOS/TetherBar"
cp Info.plist "$app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$version" "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
codesign --force --sign - --options runtime --identifier com.hiva.TetherBar "$app"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
"$app/Contents/MacOS/TetherBar" --self-test
"$app/Contents/MacOS/TetherBar" --version
rm -rf build/TetherBar.app
mv "$app" build/TetherBar.app
