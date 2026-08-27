#!/usr/bin/env bash
# Build the Chromebook edition of the course.
#
#   bash ~/claude-code-course/chromeos/build-chromebook.sh
#
# Produces two things, because a Chromebook can take the course two ways:
#
#   chromeos/Claude Code Academy (Chromebook).html   the file build
#   docs/                                            the installable build
#
# THE FILE BUILD is one .html. Put it in the student's Downloads, they
# double-click it in the Files app and Chrome opens it. No install, no
# account, no network, ever. This is the one to attach to a GitHub release.
#
# THE INSTALLABLE BUILD is the same course plus a manifest and a service
# worker, laid out for GitHub Pages. The student visits the URL once, clicks
# "Install as an app", and gets a shelf icon and an offline copy. On ChromeOS
# this is the native app — there is no .exe to ship, so a PWA is the thing
# the win/ and linux/ builds are for everywhere else.
#
# Both are the standalone desktop build with chromeos/enhance.html spliced in
# before </body> — short-screen sizing, tablet-mode touch targets, swipe, and
# the install button. index.html is never edited for ChromeOS.
#
# Re-run this after any edit to index.html.
#
# Requires: python3, imagemagick.

set -euo pipefail

# Derived from this script's own location, and overridable like make-icon.sh,
# so the repo still builds from a worktree or a clone outside $HOME.
SRC_DIR="${SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export SRC_DIR
CB_DIR="$SRC_DIR/chromeos"
PWA_SRC="$CB_DIR/pwa"
DOCS="$SRC_DIR/docs"

SRC="$SRC_DIR/index.html"
DESKTOP_BUILD="$SRC_DIR/claude-code-academy.html"
ENHANCE="$CB_DIR/enhance.html"
APP_NAME="Claude Code Academy"
FILE_BUILD="$CB_DIR/$APP_NAME (Chromebook).html"

# Failures go to stderr: the app builds call helper scripts with stdout
# redirected to /dev/null, and a message on stdout would simply vanish.
die() { printf '%s\n' "$@" >&2; exit 1; }

[ -f "$SRC" ]     || die "error: $SRC not found"
[ -f "$ENHANCE" ] || die "error: $ENHANCE not found"

command -v python3 >/dev/null 2>&1 || die "error: python3 not found"

# ImageMagick 7 renamed the binary. Support both rather than assuming.
if command -v magick >/dev/null 2>&1; then IM="magick"
elif command -v convert >/dev/null 2>&1; then IM="convert"
else die "error: ImageMagick not found (need 'magick' or 'convert')"; fi

# ------------------------------------------------------------------ the course
# Always regenerate the desktop build first, so the Chromebook edition can never
# be a rebuild behind the course.
echo "→ regenerating the desktop build first"
bash "$SRC_DIR/build-app.sh" > /dev/null
[ -f "$DESKTOP_BUILD" ] || die "error: $DESKTOP_BUILD was not produced"

# -------------------------------------------------------------------- the icon
# The launcher icon is the same emoji render every other platform uses, so the
# installed web app matches the .exe and the .apk on a student's machine.
[ -f "$SRC_DIR/icon.png" ] || bash "$SRC_DIR/make-icon.sh" > /dev/null
[ -f "$SRC_DIR/icon.png" ] || die "error: $SRC_DIR/icon.png was not produced"

CARD="#171f1c"   # --card, the same plate colour the iOS and Android icons use

mkdir -p "$DOCS"

# "any" icons: the glyph on an opaque plate, filling the canvas.
# -alpha remove composites the transparent emoji render onto CARD and -alpha
# off drops the channel entirely. Both matter: a launcher icon with holes in
# it shows whatever is behind it, which on ChromeOS is the shelf.
for px in 192 512; do
  "$IM" "$SRC_DIR/icon.png" -resize "${px}x${px}" \
    -background "$CARD" -gravity center -extent "${px}x${px}" \
    -alpha remove -alpha off -strip -define png:compression-level=9 \
    "$DOCS/icon-$px.png"
done

# Maskable icon: ChromeOS crops this to whatever shape the launcher wants, and
# only the middle 80% is guaranteed to survive. Anything drawn outside that
# safe zone can be sliced off, so the glyph is inset to 66% and the plate does
# the rest — a circular crop then still lands entirely on background.
SAFE=$((512 * 66 / 100))
"$IM" "$SRC_DIR/icon.png" -resize "${SAFE}x${SAFE}" \
  -background "$CARD" -gravity center -extent "512x512" \
  -alpha remove -alpha off -strip -define png:compression-level=9 \
  "$DOCS/icon-maskable-512.png"

# ------------------------------------------------------------------- the build
python3 - "$DESKTOP_BUILD" "$ENHANCE" "$FILE_BUILD" "$DOCS/index.html" <<'PY'
import hashlib, pathlib, re, sys

deck_path, enhance_path, file_out, docs_out = sys.argv[1:]
deck = pathlib.Path(deck_path).read_text(encoding="utf-8")
enhance = pathlib.Path(enhance_path).read_text(encoding="utf-8")

marker = "</body>"
if deck.count(marker) != 1:
    sys.exit(f"error: expected exactly one {marker}, found {deck.count(marker)}")

out = deck.replace(marker, enhance + "\n" + marker)

# The Chromebook edition must be self-contained. The file build has no server
# to fetch from, and the installed build has to survive a bus ride, so a
# silently-missing stylesheet is a blank course either way.
external = re.findall(r'(?:src|href)="https?://[^"]+"', out)
if external:
    sys.exit("error: external requests found in the Chromebook build:\n  " + "\n  ".join(external))

# ---- the file build: opened from the Files app, nothing to install ----------
pathlib.Path(file_out).write_text(out, encoding="utf-8")
print(f"  wrote {file_out}  ({len(out.encode('utf-8'))/1024:.0f} KB)")

# ---- the installable build: the same page, plus a manifest link ------------
# The link belongs in <head>. It is added only here: pointing the file build at
# a manifest that does not sit beside it would just be a console error.
head_marker = "</head>"
if out.count(head_marker) != 1:
    sys.exit(f"error: expected exactly one {head_marker}, found {out.count(head_marker)}")

hosted = out.replace(
    head_marker,
    '<link rel="manifest" href="manifest.webmanifest">\n' + head_marker,
)

docs_path = pathlib.Path(docs_out)
docs_path.parent.mkdir(parents=True, exist_ok=True)
docs_path.write_text(hosted, encoding="utf-8")
print(f"  wrote {docs_out}  ({len(hosted.encode('utf-8'))/1024:.0f} KB)")

# The cache name is a hash of the page. A rebuilt course is a new cache, which
# is what evicts the stale one from an already-installed copy.
version = hashlib.sha256(hosted.encode("utf-8")).hexdigest()[:12]
print(f"  version {version}")
pathlib.Path(docs_path.parent / ".cca-version").write_text(version, encoding="utf-8")
PY

VERSION="$(cat "$DOCS/.cca-version")"
rm -f "$DOCS/.cca-version"

# The manifest is copied verbatim; the worker gets its cache name stamped in.
cp -f "$PWA_SRC/manifest.webmanifest" "$DOCS/manifest.webmanifest"
sed "s/__CCA_VERSION__/$VERSION/g" "$PWA_SRC/sw.js" > "$DOCS/sw.js"
grep -q "__CCA_VERSION__" "$DOCS/sw.js" && die "error: version placeholder not substituted"

# GitHub Pages runs everything through Jekyll unless told not to, and Jekyll
# skips files and folders whose names start with an underscore. Nothing here
# does today, but this costs one empty file and removes a whole class of
# "it works locally" bug reports.
: > "$DOCS/.nojekyll"

# ------------------------------------------------------------------ handing it over
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -n "$DESKTOP_DIR" ] && [ -d "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"
cp -f "$FILE_BUILD" "$DESKTOP_DIR/$APP_NAME (Chromebook).html"

echo
echo "built:  $FILE_BUILD"
echo "        $(du -h "$FILE_BUILD" | cut -f1) — one file, works offline, nothing to install"
echo "copy:   $DESKTOP_DIR/$APP_NAME (Chromebook).html"
echo "site:   $DOCS/   (commit it, then turn on GitHub Pages -> Deploy from branch -> /docs)"
echo
echo "Sanity check — external requests in the built file (should be 0):"
grep -cE '(src|href)="https?://' "$FILE_BUILD" || true
echo
echo "To share it: send the single .html, or send the Pages URL and tell them"
echo "to click \"Install as an app\"."
