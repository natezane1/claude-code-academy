#!/usr/bin/env bash
# Build the phone edition of the course and drop it into both app projects.
#
#   bash ~/claude-code-course/build-mobile.sh
#
# Produces:
#   android/app/src/main/assets/course.html
#   ios/ClaudeCodeAcademy/Resources/course.html
#
# Both apps ship the SAME file. It is the standalone desktop build with
# mobile/enhance.html spliced in before </body> — touch navigation, safe-area
# padding and the back-gesture handler. index.html is never edited for mobile.
#
# Re-run this after any edit to index.html, then rebuild whichever app you want:
#   android/build-apk.sh          a real installable .apk
#   ios/  -> open in Xcode on a Mac
set -euo pipefail

SRC_DIR="$HOME/claude-code-course"
DESKTOP_BUILD="$SRC_DIR/claude-code-academy.html"
ENHANCE="$SRC_DIR/mobile/enhance.html"
ANDROID_OUT="$SRC_DIR/android/app/src/main/assets/course.html"
IOS_OUT="$SRC_DIR/ios/ClaudeCodeAcademy/Resources/course.html"

[ -f "$ENHANCE" ] || { echo "error: $ENHANCE not found"; exit 1; }

# Always regenerate the desktop build first, so the phone edition can never be
# a rebuild behind the course. Cheap, and removes a whole class of "why is my
# fix not showing up on the phone".
echo "→ regenerating the desktop build first"
bash "$SRC_DIR/build-app.sh" > /dev/null
[ -f "$DESKTOP_BUILD" ] || { echo "error: $DESKTOP_BUILD was not produced"; exit 1; }

# Splice the enhancement layer in immediately before </body>. Done in Python
# rather than sed because the payload is multi-line HTML containing slashes,
# ampersands and backreference-looking text, all of which sed would mangle.
python3 - "$DESKTOP_BUILD" "$ENHANCE" "$ANDROID_OUT" "$IOS_OUT" <<'PY'
import pathlib, sys

deck_path, enhance_path, *out_paths = sys.argv[1:]
deck = pathlib.Path(deck_path).read_text(encoding="utf-8")
enhance = pathlib.Path(enhance_path).read_text(encoding="utf-8")

marker = "</body>"
if deck.count(marker) != 1:
    sys.exit(f"error: expected exactly one {marker}, found {deck.count(marker)}")

out = deck.replace(marker, enhance + "\n" + marker)

# The phone build must be self-contained: an app with no network permission
# cannot fetch anything, and a silently-missing stylesheet is a blank course.
import re
external = re.findall(r'(?:src|href)="https?://[^"]+"', out)
if external:
    sys.exit("error: external requests found in the phone build:\n  " + "\n  ".join(external))

for p in out_paths:
    path = pathlib.Path(p)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(out, encoding="utf-8")
    print(f"  wrote {path}  ({len(out.encode('utf-8'))/1024:.0f} KB)")
PY

echo
echo "phone edition built — identical file in both apps, fully offline."
echo "  android:  bash $SRC_DIR/android/build-apk.sh"
echo "  ios:      open $SRC_DIR/ios/ClaudeCodeAcademy.xcodeproj   (needs a Mac)"
