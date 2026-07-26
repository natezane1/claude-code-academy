#!/usr/bin/env bash
# Render the app icon — the 🤖 the course uses on its own slides and as its
# favicon — into the formats the two app builds need.
#
#   bash ~/claude-code-course/make-icon.sh
#
# Produces:
#   ~/claude-code-course/icon.png   256px, transparent   (Linux window + launcher)
#   ~/claude-code-course/icon.ico   multi-size           (Windows .exe)
#
# Both app builds call this, so the icon has exactly one source: the emoji.
# Rendering goes through Pango rather than ImageMagick's text engine, because
# only Pango/Cairo understands the colour bitmap tables in an emoji font — the
# plain -font path silently gives you a flat monochrome glyph.

set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/claude-code-course}"
EMOJI="🤖"
SIZE=256          # nominal canvas; the emoji is drawn large then centred in it
POINT=180         # point size that fills that canvas without clipping

# Failures go to stderr, because the app builds call this script with stdout
# redirected to /dev/null — on stdout these messages would vanish and the build
# would just stop with no explanation.
die() { printf '%s\n' "$@" >&2; exit 1; }

command -v magick >/dev/null 2>&1 ||
  die "error: imagemagick not found"

# Deliberately not `... | grep -q`: grep -q exits on the first match, the
# producer gets SIGPIPE, and under `set -o pipefail` that makes the whole
# pipeline report failure even though the check passed. Capture, then match.
FONTS="$(fc-list 2>/dev/null || true)"
case "$FONTS" in
  *"Noto Color Emoji"*) ;;
  *) die "error: Noto Color Emoji font not found" \
         "       sudo apt install fonts-noto-color-emoji" ;;
esac

FORMATS="$(magick -list format 2>/dev/null || true)"
case "$FORMATS" in
  *PANGO*) ;;
  *) die "error: this ImageMagick has no Pango delegate, so colour emoji cannot" \
         "       be rendered. sudo apt install libpango1.0-dev, or reinstall" \
         "       imagemagick from a build that includes it." ;;
esac

# Trim to the glyph, then centre it on a square transparent canvas with a little
# breathing room, so it does not touch the edges of a taskbar tile.
magick -background none \
  pango:"<span font=\"Noto Color Emoji $POINT\">$EMOJI</span>" \
  -trim +repage \
  -resize "$((SIZE * 88 / 100))x$((SIZE * 88 / 100))" \
  -background none -gravity center -extent "${SIZE}x${SIZE}" \
  "$SRC_DIR/icon.png"

# Windows wants every size in one file: 16px for Explorer lists and the taskbar,
# 256px for large icons and Alt-Tab.
magick "$SRC_DIR/icon.png" \
  -define icon:auto-resize=256,128,64,48,32,16 \
  "$SRC_DIR/icon.ico"

echo "icon: $SRC_DIR/icon.png  ($(magick identify -format '%wx%h' "$SRC_DIR/icon.png"))"
echo "icon: $SRC_DIR/icon.ico  ($(magick identify "$SRC_DIR/icon.ico" | wc -l) sizes)"
