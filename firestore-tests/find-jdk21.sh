#!/bin/sh
# Print a JAVA_HOME for a JDK >= 21, which firebase-tools requires to run the
# Firestore emulator. Deliberately does NOT touch the default `java`: the Android
# build is pinned to JDK 17 (see CLAUDE.md) and must stay there.
#
# Android Studio bundles a JBR 21, so on a normal dev machine here there is
# nothing to install.
set -e

for candidate in \
  "$JAVA_HOME" \
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  "$(/usr/libexec/java_home -v 21+ 2>/dev/null || true)"
do
  [ -n "$candidate" ] || continue
  [ -x "$candidate/bin/java" ] || continue
  version=$("$candidate/bin/java" -version 2>&1 | head -1 | sed 's/.*version "\([0-9]*\).*/\1/')
  if [ -n "$version" ] && [ "$version" -ge 21 ] 2>/dev/null; then
    printf '%s' "$candidate"
    exit 0
  fi
done

echo "No JDK >= 21 found; the Firestore emulator needs one." >&2
echo "Install with: brew install openjdk@21  (keg-only, leaves your default java alone)" >&2
exit 1
