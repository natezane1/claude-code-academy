#!/usr/bin/env bash
# Build the shareable, offline HTML build of Claude Code Academy.
#
#   bash ~/claude-code-course/build-app.sh
#
# Produces:
#   ~/claude-code-course/claude-code-academy.html   the whole course in one file
#   ~/Desktop/Claude Code Academy (Any OS).html     a copy you can double-click
#
# This is the plain HTML build — it opens in a browser, and it is what you send
# to someone who just wants a file. The real apps wrap this same file:
#
#   linux/build-linux-app.sh   own window, no browser   (also writes the launcher)
#   win/build-exe.sh           Windows .exe
#
# Both of those call this script when index.html is newer, so editing the course
# and rebuilding an app is a single command.
#
# Re-run this after any edit to index.html.

set -euo pipefail

SRC_DIR="$HOME/claude-code-course"
SRC="$SRC_DIR/index.html"
APP_NAME="Claude Code Academy"
# The launcher target deliberately has NO spaces in its path: a .desktop Exec
# line is split on whitespace, so a spaced path silently becomes two arguments
# and the launcher fails. The friendly, spaced name is the Desktop copy.
OUT="$SRC_DIR/claude-code-academy.html"

[ -f "$SRC" ] || { echo "error: $SRC not found"; exit 1; }

DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -n "$DESKTOP_DIR" ] && [ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"

# ---------------------------------------------------------------- the app file
# index.html is a body fragment (that is the format the Artifact host wants).
# Here we wrap it into a complete, standalone HTML document so it works when
# opened straight off the filesystem, with no server and no network.
{
  cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="Learn Claude Code one slide at a time — 14 levels, from never having opened a terminal to building an agent loop.">
<!-- the course is dark by default, so tell the browser that outright: it keeps
     scrollbars, form controls and mobile browser chrome from flashing light -->
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#0f1513">
<!-- lets it run chromeless when installed or launched in app mode -->
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Claude Code Academy">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Ctext y='.9em' font-size='90'%3E%F0%9F%A4%96%3C/text%3E%3C/svg%3E">
<title>Claude Code Academy — Coach Your Robot Crew</title>
<style>
  /* the host page normally supplies a reset; standalone build needs its own */
  html { -webkit-text-size-adjust: 100%; }
  body { margin: 0; }
</style>
</head>
<body>
HEAD

  # The course itself. Drop its leading <title>: that line exists for the
  # Artifact host to hoist into <head>, and here it would be a second title
  # sitting inside <body>.
  sed '1{/^<title>.*<\/title>[[:space:]]*$/d;}' "$SRC"

  cat <<'FOOT'
</body>
</html>
FOOT
} > "$OUT"

# Labelled "Any OS" to sit unambiguously beside the Windows and Linux apps:
# this one is the plain file that opens in a browser anywhere.
cp -f "$OUT" "$DESKTOP_DIR/$APP_NAME (Any OS).html"
rm -f "$DESKTOP_DIR/$APP_NAME.html"

# tidy up the spaced build produced by the first version of this script
rm -f "$SRC_DIR/$APP_NAME.html"

# The desktop launcher deliberately is NOT written here. It belongs to the
# native app, which owns its own window — see linux/build-linux-app.sh. Writing
# a browser-based launcher from this script would quietly undo that.

echo "built:  $OUT"
echo "        $(du -h "$OUT" | cut -f1) — single file, works offline, nothing external"
echo "share:  $DESKTOP_DIR/$APP_NAME (Any OS).html   (double-click, or send to anyone)"
echo "app:    bash $SRC_DIR/linux/build-linux-app.sh   for the own-window build"
echo
echo "Sanity check — external requests in the built file (should be 0):"
grep -cE '(src|href)="https?://' "$OUT" || true
echo
echo "To share it: send the single .html file. The recipient double-clicks it."
