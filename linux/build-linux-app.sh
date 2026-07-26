#!/usr/bin/env bash
# Build the Linux app: one executable file, the whole course inside it, opening
# in its own window.
#
#   bash ~/claude-code-course/linux/build-linux-app.sh
#
# Produces:
#   ~/claude-code-course/linux/claude-code-academy     the app — send this to Linux users
#   ~/Desktop/Claude Code Academy (Linux)              a copy you can double-click
#   ~/.local/share/applications/…                    entry in the app menu
#
# Needs nothing to build. To run, the machine needs PyGObject and WebKitGTK:
#   sudo apt install python3-gi gir1.2-webkit2-4.1 gir1.2-gtk-3.0
# (all standard on Debian/Ubuntu/Kali desktops; the app says so if they are
# missing, and falls back to opening the course in a browser).

set -euo pipefail

SRC_DIR="$HOME/claude-code-course"
LINUX_DIR="$SRC_DIR/linux"
HTML="$SRC_DIR/claude-code-academy.html"
APP_NAME="Claude Code Academy"
# No spaces: a .desktop Exec line is split on whitespace, so a spaced path
# silently becomes two arguments. The spaced name is the Desktop copy.
APP="$LINUX_DIR/claude-code-academy"
ICON_PNG="$LINUX_DIR/icon.png"

command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found"; exit 1; }
command -v magick   >/dev/null 2>&1 || { echo "error: imagemagick not found"; exit 1; }

# ------------------------------------------------------------------ the course
if [ ! -f "$HTML" ] || [ "$SRC_DIR/index.html" -nt "$HTML" ]; then
  echo "index.html is newer than the standalone build — running build-app.sh first"
  bash "$SRC_DIR/build-app.sh" >/dev/null
fi

# -------------------------------------------------------------------- the icon
bash "$SRC_DIR/make-icon.sh" >/dev/null
cp -f "$SRC_DIR/icon.png" "$ICON_PNG"

# ------------------------------------------------------- the single-file build
# The app is academy.py with the course and the icon appended: gzipped, base64'd,
# one line each, behind a marker the script knows how to find.
cp -f "$LINUX_DIR/academy.py" "$APP"

{
  echo
  echo "#---COURSE-HTML---"
  printf '#'
  gzip -9 -c "$HTML" | base64 -w 0
  echo
  echo "#---COURSE-ICON---"
  printf '#'
  gzip -9 -c "$ICON_PNG" | base64 -w 0
  echo
} >> "$APP"

chmod +x "$APP"

python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$APP"

# ---------------------------------------------------------------- the launcher
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -n "$DESKTOP_DIR" ] && [ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"
# The filename carries the OS: there is a Windows build of the same course
# sitting next to this one, and a Linux binary has no extension to tell them
# apart. The executable the launcher points at keeps its plain, unspaced name.
cp -f "$APP" "$DESKTOP_DIR/$APP_NAME (Linux)"
chmod +x "$DESKTOP_DIR/$APP_NAME (Linux)"
# tidy up the unlabelled copy produced by the first version of this script
rm -f "$DESKTOP_DIR/$APP_NAME"

# StartupWMClass must match the prgname the app sets, or the running window gets
# its own anonymous entry in the dock instead of docking onto this launcher.
LAUNCHER="$DESKTOP_DIR/$APP_NAME.desktop"
cat > "$LAUNCHER" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Claude Code Academy
GenericName=Claude Code course
Comment=Learn Claude Code one slide at a time
Exec=$APP
Icon=$ICON_PNG
Terminal=false
Categories=Education;Development;
Keywords=claude;code;course;learn;ai;
StartupWMClass=claude-code-academy
EOF

chmod +x "$LAUNCHER"
command -v gio >/dev/null 2>&1 && gio set "$LAUNCHER" metadata::trusted true 2>/dev/null || true

mkdir -p "$HOME/.local/share/applications"
cp -f "$LAUNCHER" "$HOME/.local/share/applications/claude-code-academy.desktop"
command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

echo
echo "built:    $APP"
echo "          $(du -h "$APP" | cut -f1) — one file, own window, works offline"
echo "copy:     $DESKTOP_DIR/$APP_NAME (Linux)"
echo "launcher: $LAUNCHER   (also in your app menu)"
echo
echo "To share it: send the single file. The recipient marks it executable and runs it."
