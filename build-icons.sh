#!/usr/bin/env bash
# Generate every app-store icon size for both phone apps from the one robot.
#
#   bash ~/claude-code-course/build-icons.sh
#
# Source is icon.png — the 🤖 rendered by make-icon.sh. This script only ever
# resizes and pads it, so re-running make-icon.sh and then this one is the whole
# path from "change the emoji" to "both stores have the right icon".
#
# Writes:
#   android/app/src/main/res/mipmap-*/ic_launcher.png            legacy, API < 26
#   android/app/src/main/res/mipmap-*/ic_launcher_round.png      legacy round
#   android/app/src/main/res/mipmap-*/ic_launcher_foreground.png adaptive, API 26+
#   ios/ClaudeCodeAcademy/Assets.xcassets/AppIcon.appiconset/*.png
set -euo pipefail

SRC_DIR="$HOME/claude-code-course"
SRC="$SRC_DIR/icon.png"
AND_RES="$SRC_DIR/android/app/src/main/res"
IOS_ICON="$SRC_DIR/ios/ClaudeCodeAcademy/Assets.xcassets/AppIcon.appiconset"

die() { printf '%s\n' "$@" >&2; exit 1; }

[ -f "$SRC" ] || die "error: $SRC not found — run: bash $SRC_DIR/make-icon.sh"

# ImageMagick 7 renamed the binary. Support both rather than assuming.
if command -v magick >/dev/null 2>&1; then IM="magick"
elif command -v convert >/dev/null 2>&1; then IM="convert"
else die "error: ImageMagick not found (need 'magick' or 'convert')"; fi

CARD="#171f1c"   # --card, matches @color/icon_bg in the adaptive icon

# ---------------------------------------------------------------- Android
# density : legacy px : adaptive foreground px
# Legacy launcher icons are 48dp; adaptive foregrounds are 108dp. Both scale by
# the same density multiplier (mdpi 1x, hdpi 1.5x, xhdpi 2x, xxhdpi 3x, xxxhdpi 4x).
for row in "mdpi:48:108" "hdpi:72:162" "xhdpi:96:216" "xxhdpi:144:324" "xxxhdpi:192:432"; do
  IFS=: read -r density legacy fg <<< "$row"
  out="$AND_RES/mipmap-$density"
  mkdir -p "$out"

  # Legacy square: robot on the card colour, filling the tile the way pre-API-26
  # launchers expect (they apply no mask of their own).
  "$IM" "$SRC" -resize "${legacy}x${legacy}" -background "$CARD" -gravity center \
        -extent "${legacy}x${legacy}" "$out/ic_launcher.png"

  # Legacy round: same tile, circle-masked, for launchers that ask for roundIcon.
  # DstIn against a drawn white disc is the readable way to do this; the
  # -fx clone/flip variants that circulate for the same job are far harder to
  # check and fail differently between ImageMagick 6 and 7.
  half=$(( legacy / 2 ))
  "$IM" "$SRC" -resize "${legacy}x${legacy}" -background "$CARD" -gravity center \
        -extent "${legacy}x${legacy}" \
        \( -size "${legacy}x${legacy}" xc:none -fill white \
           -draw "circle ${half},${half} ${half},0" \) \
        -alpha set -compose DstIn -composite "$out/ic_launcher_round.png"

  # Adaptive foreground: 108dp canvas, transparent, robot confined to the inner
  # 72dp safe zone (66%). The launcher mask crops the outer ring on some shapes,
  # so anything drawn out there is a gamble.
  safe=$(( fg * 66 / 100 ))
  "$IM" "$SRC" -resize "${safe}x${safe}" -background none -gravity center \
        -extent "${fg}x${fg}" "$out/ic_launcher_foreground.png"
done

# ---------------------------------------------------------------- iOS
# Xcode 14+ takes a single 1024x1024 and derives the rest, but shipping the
# explicit set keeps the icon correct on older Xcode and makes the appiconset
# readable without opening Xcode.
mkdir -p "$IOS_ICON"
# App Store artwork must have NO alpha channel — an icon with transparency is
# rejected at upload. Flatten onto the card colour rather than leaving it.
for px in 1024 180 167 152 120 87 80 76 60 58 40 29 20; do
  "$IM" "$SRC" -resize "${px}x${px}" -background "$CARD" -gravity center \
        -extent "${px}x${px}" -alpha remove -alpha off \
        "$IOS_ICON/icon-${px}.png"
done

echo "icons built:"
echo "  android : $(find "$AND_RES" -name 'ic_launcher*.png' | wc -l) files across 5 densities"
echo "  ios     : $(find "$IOS_ICON" -name 'icon-*.png' | wc -l) sizes, alpha stripped"
echo
echo "alpha check (App Store rejects icons with transparency):"
"$IM" identify -format '  %f  %[channels]\n' "$IOS_ICON/icon-1024.png"
