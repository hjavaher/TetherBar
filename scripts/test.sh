#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/tetherbar-tests.XXXXXX")
trap 'rm -rf "$out"' EXIT HUP INT TERM
xcrun clang -O1 -g -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
  -Wno-nonnull -mmacosx-version-min=13.0 -framework Foundation \
  HBProbe.m tests/ProbeTests.m -o "$out/probe-tests"
"$out/probe-tests"
for source in TetherBar.m HBProbe.m; do
  report="$out/$source.plist"
  xcrun clang --analyze -fobjc-arc -mmacosx-version-min=13.0 \
    -Xanalyzer -analyzer-output=plist -o "$report" "$source"
  if [ "$(/usr/libexec/PlistBuddy -c 'Print :diagnostics' "$report")" != 'Array {
}' ]; then
    echo "Static analyzer reported findings in $source" >&2
    exit 1
  fi
done
echo 'PASS: Clang static analysis (zero diagnostics)'
