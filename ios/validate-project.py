#!/usr/bin/env python3
"""
Structural check for the hand-written Xcode project.

This exists because the iOS app cannot be compiled on the machine it was
written on — there is no Xcode outside macOS. Everything that CAN be checked
without a compiler is checked here, so the only unknown left when it reaches a
Mac is Swift type-checking rather than "does the project even open".

What it verifies:

  * project.pbxproj parses as an OpenStep plist
  * every object ID referenced anywhere resolves to a real object
  * every PBXFileReference points at a file that exists on disk
  * every PBXBuildFile's fileRef exists, and each source/resource lands in
    the right build phase
  * Info.plist parses, and the keys the App Store requires are present
  * every asset catalog Contents.json parses, and each image it names exists
  * the app icon has no alpha channel (App Store rejects icons that do)

Run:  python3 ios/validate-project.py
Exit: 0 all good · 1 something is wrong (details on stdout)
"""

from __future__ import annotations

import json
import plistlib
import re
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PBXPROJ = HERE / "ClaudeCodeAcademy.xcodeproj" / "project.pbxproj"
APP_DIR = HERE / "ClaudeCodeAcademy"

problems: list[str] = []
checks = 0


def ok(msg: str) -> None:
    global checks
    checks += 1
    print(f"  ok    {msg}")


def bad(msg: str) -> None:
    problems.append(msg)
    print(f"  FAIL  {msg}")


# --------------------------------------------------------------- pbxproj
# A minimal OpenStep-plist reader. Python ships no parser for the format and
# pulling a dependency in to check one file would be worse than 60 lines.
class OpenStepParser:
    def __init__(self, text: str) -> None:
        # Strip // line comments and /* block comments */ first. Neither format
        # nests, and no string in a pbxproj legitimately contains them.
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        text = re.sub(r"//[^\n]*", " ", text)
        self.s = text
        self.i = 0

    def ws(self) -> None:
        while self.i < len(self.s) and self.s[self.i] in " \t\r\n":
            self.i += 1

    def parse(self):
        self.ws()
        return self.value()

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "{":
            return self.dict()
        if c == "(":
            return self.array()
        if c == '"':
            return self.quoted()
        return self.bare()

    def dict(self) -> dict:
        out: dict = {}
        self.i += 1  # {
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                return out
            key = self.quoted() if self.s[self.i] == '"' else self.bare()
            self.ws()
            assert self.s[self.i] == "=", f"expected = at {self.i}"
            self.i += 1
            out[key] = self.value()
            self.ws()
            if self.s[self.i] == ";":
                self.i += 1

    def array(self) -> list:
        out: list = []
        self.i += 1  # (
        while True:
            self.ws()
            if self.s[self.i] == ")":
                self.i += 1
                return out
            out.append(self.value())
            self.ws()
            if self.s[self.i] == ",":
                self.i += 1

    def quoted(self) -> str:
        self.i += 1  # "
        buf = []
        while self.s[self.i] != '"':
            if self.s[self.i] == "\\":
                self.i += 1
            buf.append(self.s[self.i])
            self.i += 1
        self.i += 1
        return "".join(buf)

    def bare(self) -> str:
        start = self.i
        while self.s[self.i] not in " \t\r\n;,=(){}":
            self.i += 1
        return self.s[start:self.i]


print("project.pbxproj")
if not PBXPROJ.exists():
    bad(f"{PBXPROJ} does not exist")
    sys.exit(1)

try:
    proj = OpenStepParser(PBXPROJ.read_text(encoding="utf-8")).parse()
    ok("parses as an OpenStep plist")
except Exception as exc:  # noqa: BLE001 - any parse failure is equally fatal
    bad(f"does not parse: {exc}")
    sys.exit(1)

objects = proj.get("objects", {})
ok(f"{len(objects)} objects, rootObject = {proj.get('rootObject')}")

# Every 24-hex-char token in the file should name a real object.
ID_RE = re.compile(r"\b[0-9A-F]{24}\b")
referenced = set(ID_RE.findall(re.sub(r"/\*.*?\*/", " ", PBXPROJ.read_text(), flags=re.S)))
dangling = sorted(referenced - set(objects))
if dangling:
    bad(f"references to objects that do not exist: {dangling}")
else:
    ok(f"all {len(referenced)} object references resolve")

unreferenced = sorted(set(objects) - referenced - {proj.get("rootObject")})
if unreferenced:
    bad(f"orphaned objects nothing points at: {unreferenced}")
else:
    ok("no orphaned objects")

# Files named by the project must actually be there.
for oid, obj in objects.items():
    if obj.get("isa") != "PBXFileReference":
        continue
    if obj.get("sourceTree") == "BUILT_PRODUCTS_DIR":
        continue  # produced by the build, not on disk
    path = obj.get("path", "")
    # Resolve through the group that owns it.
    owner = next(
        (g for g in objects.values()
         if g.get("isa") == "PBXGroup" and oid in g.get("children", [])),
        None,
    )
    prefix = Path()
    while owner is not None:
        if owner.get("path"):
            prefix = Path(owner["path"]) / prefix
        owner_id = next(
            (k for k, v in objects.items() if v is owner), None
        )
        owner = next(
            (g for g in objects.values()
             if g.get("isa") == "PBXGroup" and owner_id in g.get("children", [])),
            None,
        )
    full = HERE / prefix / path
    if full.exists():
        ok(f"file exists: {prefix / path}")
    else:
        bad(f"file referenced but missing on disk: {prefix / path}")

# Build files must point at real file references, in the right phase.
src_phase = {p for o in objects.values() if o.get("isa") == "PBXSourcesBuildPhase"
             for p in o.get("files", [])}
res_phase = {p for o in objects.values() if o.get("isa") == "PBXResourcesBuildPhase"
             for p in o.get("files", [])}

for oid, obj in objects.items():
    if obj.get("isa") != "PBXBuildFile":
        continue
    ref = obj.get("fileRef")
    target = objects.get(ref, {})
    name = target.get("path", "?")
    if not target:
        bad(f"build file {oid} points at missing fileRef {ref}")
        continue
    is_swift = name.endswith(".swift")
    if is_swift and oid not in src_phase:
        bad(f"{name} is Swift but is not in the Sources phase")
    elif not is_swift and oid not in res_phase:
        bad(f"{name} is a resource but is not in the Resources phase")
    else:
        ok(f"{name} is in the correct build phase")

# Every Swift file on disk should be compiled — a file that exists but was
# never added to the target is the classic hand-written-pbxproj mistake.
compiled = {objects[objects[b]["fileRef"]]["path"]
            for b in src_phase if b in objects}
for swift in sorted(APP_DIR.glob("*.swift")):
    if swift.name in compiled:
        ok(f"{swift.name} is compiled")
    else:
        bad(f"{swift.name} exists on disk but is in no target")

# --------------------------------------------------------------- Info.plist
print("\nInfo.plist")
info_path = APP_DIR / "Info.plist"
try:
    info = plistlib.loads(info_path.read_bytes())
    ok("parses as a plist")
except Exception as exc:  # noqa: BLE001
    bad(f"does not parse: {exc}")
    info = {}

for key in (
    "CFBundleIdentifier", "CFBundleName", "CFBundleShortVersionString",
    "CFBundleVersion", "CFBundleExecutable", "UILaunchScreen",
    "UISupportedInterfaceOrientations", "LSRequiresIPhoneOS",
):
    if key in info:
        ok(f"{key} present")
    else:
        bad(f"{key} missing — App Store submission requires it")

if info.get("ITSAppUsesNonExemptEncryption") is False:
    ok("ITSAppUsesNonExemptEncryption = false (no export-compliance prompt)")

# --------------------------------------------------------------- assets
print("\nAssets.xcassets")
for contents in sorted(APP_DIR.rglob("Contents.json")):
    rel = contents.relative_to(APP_DIR)
    try:
        data = json.loads(contents.read_text())
        ok(f"{rel} parses")
    except Exception as exc:  # noqa: BLE001
        bad(f"{rel} is not valid JSON: {exc}")
        continue
    for image in data.get("images", []):
        fn = image.get("filename")
        if fn and not (contents.parent / fn).exists():
            bad(f"{rel} names {fn}, which is not there")

icon = APP_DIR / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
if icon.exists():
    # PNG colour type lives at byte 25 of the IHDR chunk. 4 and 6 carry alpha,
    # and App Store Connect rejects a marketing icon with any transparency.
    head = icon.read_bytes()[:26]
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        width, height = struct.unpack(">II", head[16:24])
        colour_type = head[25]
        if (width, height) != (1024, 1024):
            bad(f"marketing icon is {width}x{height}, must be 1024x1024")
        else:
            ok("marketing icon is 1024x1024")
        if colour_type in (4, 6):
            bad("marketing icon has an alpha channel — App Store will reject it")
        else:
            ok("marketing icon has no alpha channel")
else:
    bad("icon-1024.png missing — run build-icons.sh")

# --------------------------------------------------------------- course
print("\nBundled course")
course = APP_DIR / "Resources" / "course.html"
if course.exists():
    text = course.read_text(encoding="utf-8")
    ok(f"course.html present ({len(text.encode()) / 1024:.0f} KB)")
    external = re.findall(r'(?:src|href)="https?://[^"]+"', text)
    if external:
        bad(f"course.html makes {len(external)} external request(s); the app has no network")
    else:
        ok("course.html is fully self-contained")
    if "mobile-enhance" in text:
        ok("mobile enhancement layer is spliced in")
    else:
        bad("mobile enhancement layer missing — run build-mobile.sh")
else:
    bad("Resources/course.html missing — run build-mobile.sh")

# --------------------------------------------------------------- verdict
print()
if problems:
    print(f"{len(problems)} problem(s) found:")
    for p in problems:
        print(f"  · {p}")
    sys.exit(1)

print(f"All {checks} structural checks passed.")
print("NOT checked: Swift compilation, code signing, runtime behaviour.")
print("Those need Xcode on macOS — see ios/README.md.")
