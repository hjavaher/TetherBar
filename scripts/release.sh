#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
cd "$(dirname "$0")/.."
mode=${1:-preview}
case "$mode" in preview|notarized) ;; *) echo 'Usage: sh scripts/release.sh [preview|notarized]' >&2; exit 1;; esac
python3 scripts/check-public.py
version=$(cat VERSION)
destination="$PWD/dist/$version-$mode"
if [ -e "$destination" ] || [ -L "$destination" ] || [ -L dist ]; then
  echo 'Release destination exists or is a symlink; refusing to replace it.' >&2
  exit 1
fi
if [ "$mode" = notarized ]; then
  : "${TETHERBAR_SIGN_IDENTITY:?Set a Developer ID Application identity from Keychain}"
  : "${TETHERBAR_NOTARY_PROFILE:?Set an existing notarytool Keychain profile name}"
fi
sh build.sh
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/.release.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
mkdir -p "$stage/output" "$stage/binary" "$stage/TetherBar-$version-source"
ditto --norsrc --noextattr build/TetherBar.app "$stage/binary/TetherBar.app"
app="$stage/binary/TetherBar.app"
if [ "$mode" = notarized ]; then
  codesign --force --sign "$TETHERBAR_SIGN_IDENTITY" --options runtime --timestamp "$app"
  codesign --verify --strict --verbose=2 "$app"
  ditto -c -k --norsrc --noextattr --keepParent "$app" "$stage/notary.zip"
  xcrun notarytool submit "$stage/notary.zip" --keychain-profile "$TETHERBAR_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi
cp LICENSE "$stage/binary/LICENSE"
cp README.md "$stage/binary/README.md"
printf 'TetherBar %s\nArchitecture: arm64 + x86_64\nDistribution: %s\n' "$version" "$mode" > "$stage/binary/BUILD-INFO.txt"
while IFS= read -r file; do
  mkdir -p "$stage/TetherBar-$version-source/$(dirname "$file")"
  cp "$file" "$stage/TetherBar-$version-source/$file"
done < PUBLIC_FILES.txt
ditto -c -k --norsrc --noextattr "$stage/binary" "$stage/output/TetherBar-$version-universal-$mode.zip"
ditto -c -k --norsrc --noextattr --keepParent "$stage/TetherBar-$version-source" "$stage/output/TetherBar-$version-source.zip"
(
  cd "$stage/output"
  shasum -a 256 ./*.zip > SHA256SUMS.txt
  shasum -a 256 -c SHA256SUMS.txt
  for archive in ./*.zip; do unzip -tq "$archive"; done
)
mv "$stage/output" "$destination"
echo "Release files: $destination"
