#!/usr/bin/env bash
# Build the Android app without Android Studio.
#
#   bash ~/claude-code-course/android/build-apk.sh          debug
#   bash ~/claude-code-course/android/build-apk.sh release   signed release + .aab
#
# This is a thin wrapper around Gradle. It exists so the Android build has the
# same shape as every other build in this repo — one script, no IDE — and so
# the three things that are easy to forget are done for you:
#
#   1. refreshing course.html from index.html before packaging
#   2. pointing Gradle at a JDK it actually supports
#   3. telling you plainly when release signing was skipped
set -euo pipefail

SRC_DIR="$HOME/claude-code-course"
APP_DIR="$SRC_DIR/android"
MODE="${1:-debug}"

die() { printf '%s\n' "$@" >&2; exit 1; }

case "$MODE" in
  debug|release) ;;
  *) die "usage: build-apk.sh [debug|release]" ;;
esac

# ---------------------------------------------------------------- toolchain
# Gradle 8.7 supports Java 17-21. A newer JDK on PATH (Kali ships 25) fails
# with an unhelpful "Unsupported class file major version", so pick a supported
# one explicitly rather than inheriting whatever java happens to be first.
if [ -z "${JAVA_HOME:-}" ] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -qE '"(17|21)\.'; then
  for candidate in /usr/lib/jvm/java-21-openjdk-* /usr/lib/jvm/java-17-openjdk-*; do
    [ -x "$candidate/bin/java" ] && { export JAVA_HOME="$candidate"; break; }
  done
fi
[ -n "${JAVA_HOME:-}" ] || die "error: no Java 17 or 21 found (apt install openjdk-21-jdk)"
export PATH="$JAVA_HOME/bin:$PATH"

# The SDK location comes from local.properties or ANDROID_HOME. Write the
# former if it is missing so Android Studio and this script agree.
if [ ! -f "$APP_DIR/local.properties" ]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/android-sdk}}"
  [ -d "$SDK/platforms" ] || die "error: no Android SDK at $SDK (set ANDROID_HOME)"
  echo "sdk.dir=$SDK" > "$APP_DIR/local.properties"
  echo "wrote $APP_DIR/local.properties -> $SDK"
fi

# ---------------------------------------------------------------- the course
# Always refresh. The APK ships a copy of the course, so skipping this silently
# packages the previous version — and nothing about the build would tell you.
echo "→ refreshing the course"
bash "$SRC_DIR/build-mobile.sh" > /dev/null
echo "  course.html $(du -h "$APP_DIR/app/src/main/assets/course.html" | cut -f1)"

# ---------------------------------------------------------------- build
cd "$APP_DIR"
GRADLE="./gradlew"
[ -x "$GRADLE" ] || GRADLE="gradle"

if [ "$MODE" = "release" ]; then
  if [ -z "${ACADEMY_KEYSTORE:-}" ]; then
    echo
    echo "note: ACADEMY_KEYSTORE is not set, so the release build will be UNSIGNED."
    echo "      An unsigned APK cannot be installed or uploaded. To sign it:"
    echo
    echo "        export ACADEMY_KEYSTORE=/path/to/release.keystore"
    echo "        export ACADEMY_KEYSTORE_PASSWORD=..."
    echo "        export ACADEMY_KEY_ALIAS=..."
    echo "        export ACADEMY_KEY_PASSWORD=..."
    echo
  fi
  "$GRADLE" assembleRelease bundleRelease
else
  "$GRADLE" assembleDebug
fi

echo
echo "built:"
find "$APP_DIR/app/build/outputs" \( -name '*.apk' -o -name '*.aab' \) -newermt '-5 minutes' \
  | while read -r f; do printf '  %-58s %s\n' "${f#$APP_DIR/}" "$(du -h "$f" | cut -f1)"; done

# ---------------------------------------------------------------- verify
# A build that succeeds and produces an APK the reader cannot install is still
# a failed build, so check the signature rather than trusting the exit code.
BT="$(ls -d "${ANDROID_HOME:-$HOME/android-sdk}"/build-tools/* 2>/dev/null | sort -V | tail -1)"
APK="$APP_DIR/app/build/outputs/apk/$MODE/app-$MODE.apk"
if [ -n "$BT" ] && [ -f "$APK" ] && [ -x "$BT/apksigner" ]; then
  echo
  echo "signature:"
  "$BT/apksigner" verify --print-certs "$APK" 2>/dev/null | grep -E 'Signer #1 certificate DN|^Verified using' | sed 's/^/  /' \
    || echo "  UNSIGNED — set the ACADEMY_* variables above"
fi
