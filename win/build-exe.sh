#!/usr/bin/env bash
# Build the Windows app: a single .exe with the whole course inside it.
#
#   bash ~/claude-code-course/win/build-exe.sh
#
# Produces:
#   ~/claude-code-course/win/Claude Code Academy (Windows).exe   send this to Windows users
#   ~/Desktop/Claude Code Academy (Windows).exe                  a copy, ready to hand over
#
# Cross-compiled here with mingw-w64 — no Windows machine needed to build it,
# and no runtime, installer, or network needed to run it.
#
# Requires: gcc-mingw-w64-x86-64, imagemagick.

set -euo pipefail

SRC_DIR="$HOME/claude-code-course"
WIN_DIR="$SRC_DIR/win"
HTML="$SRC_DIR/claude-code-academy.html"
# The filename carries the OS: there is a Linux build of the same course sitting
# next to this one, and on a desktop full of icons the extension is not enough.
EXE="$WIN_DIR/Claude Code Academy (Windows).exe"

CC=x86_64-w64-mingw32-gcc
RC=x86_64-w64-mingw32-windres
STRIP=x86_64-w64-mingw32-strip

for tool in "$CC" "$RC" "$STRIP" magick; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool not found"
    echo "       sudo apt install gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 imagemagick"
    exit 1
  }
done

# ------------------------------------------------------------------ the course
# The .exe carries the standalone build, so it has to exist and be current.
if [ ! -f "$HTML" ] || [ "$SRC_DIR/index.html" -nt "$HTML" ]; then
  echo "index.html is newer than the standalone build — running build-app.sh first"
  bash "$SRC_DIR/build-app.sh" >/dev/null
fi

cp -f "$HTML" "$WIN_DIR/payload.html"

# -------------------------------------------------------------------- the icon
bash "$SRC_DIR/make-icon.sh" >/dev/null
cp -f "$SRC_DIR/icon.ico" "$WIN_DIR/icon.ico"

# ------------------------------------------------------------------- the build
cd "$WIN_DIR"

# windres resolves the icon and payload paths relative to the .rc file.
"$RC" -i app.rc -o app.res.o -O coff

# -municode gives us wWinMain (Unicode entry point) so paths with non-ASCII
# usernames work; -mwindows means no console window flashes up on launch.
"$CC" -O2 -municode -mwindows -o "$EXE" app.c app.res.o \
  -lshlwapi -lshell32 -lole32

"$STRIP" "$EXE"

DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -n "$DESKTOP_DIR" ] && [ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"
cp -f "$EXE" "$DESKTOP_DIR/Claude Code Academy (Windows).exe"
# tidy up the unlabelled build produced by the first version of this script
rm -f "$DESKTOP_DIR/Claude Code Academy.exe" "$WIN_DIR/Claude Code Academy.exe"

echo
echo "built:  $EXE"
echo "        $(du -h "$EXE" | cut -f1) — one file, runs offline, nothing to install"
echo "copy:   $DESKTOP_DIR/Claude Code Academy (Windows).exe"
echo "target: $(file -b "$EXE")"
echo
echo "To share it: send the single .exe. The recipient double-clicks it."
