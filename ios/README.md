# Claude Code Academy — iOS

The whole 138-slide course as a native iOS app. Offline, no permissions,
no account, no network code. Universal — iPhone and iPad.

```
ios/
  ClaudeCodeAcademy.xcodeproj/       open this
  ClaudeCodeAcademy/
    AcademyApp.swift                 the App entry point
    CourseView.swift                 the WKWebView and the scheme handler
    Info.plist
    Assets.xcassets/                 app icon, accent, launch colour
    Resources/course.html            the course (generated)
  project.yml                        XcodeGen spec, if you would rather regenerate
  validate-project.py                structural check that runs anywhere
```

## ⚠️ Read this first — what has and has not been verified

**This project has never been compiled.** It was written on Linux, and Xcode
does not exist outside macOS. There is no way to build, sign, or run an iOS app
on the machine that produced it.

What *was* verified, by `validate-project.py`, which needs nothing but Python:

- `project.pbxproj` parses, every object reference resolves, nothing is orphaned
- every file the project references exists on disk, and every Swift file on disk
  is in the target — the classic hand-written-project mistake is a source file
  that quietly compiles into nothing
- `Info.plist` parses and carries every key App Store submission requires
- every asset-catalog `Contents.json` parses and names images that are present
- the 1024×1024 marketing icon has no alpha channel, which App Store Connect
  rejects outright
- the bundled course is self-contained and has the mobile layer spliced in

What was **not** verified, and cannot be from here:

- that the Swift compiles — the logic is straightforward and the APIs are used
  as documented, but a typo would only surface in Xcode
- code signing, provisioning, and anything involving a developer account
- runtime behaviour on a simulator or a device

So: expect it to open and build, but treat the first `⌘B` on a Mac as the real
test. If something is wrong it will be a Swift diagnostic on a specific line,
not a mystery.

## Build it

```bash
python3 ios/validate-project.py        # optional, runs anywhere
open ios/ClaudeCodeAcademy.xcodeproj   # on a Mac
```

Set your team under **Signing & Capabilities** (`DEVELOPMENT_TEAM` is
deliberately blank), then ⌘R.

If the project file ever gets into a state you would rather not debug,
`project.yml` regenerates it from scratch:

```bash
brew install xcodegen && cd ios && xcodegen generate
```

**Whenever you edit the course**, re-run `build-mobile.sh` before building.
The app ships a *copy* of the course in its bundle.

## How it is put together

A SwiftUI `App`, a `UIViewRepresentable` around `WKWebView`, and a URL scheme
handler. About 150 lines total, no dependencies.

The one decision worth explaining is why it does not call `loadFileURL`.

**`localStorage` does not survive `file://`.** The obvious way to load a
bundled page is `loadFileURL(_:allowingReadAccessTo:)`, and it is what most
WebView wrappers do. But WebKit treats a `file://` document as an *opaque
origin*, and an opaque origin gets no persistent local storage — writes either
throw a `SecurityError` or silently evaporate when the app relaunches. Since
`localStorage` is exactly where this course keeps your place and your badges,
that would produce an app that works perfectly in a demo and forgets everything
overnight.

So `CourseSchemeHandler` serves the bundle over a private `academy://` scheme
instead. A custom scheme is a real, stable origin, so storage behaves the way it
does in Safari. Capacitor and Ionic use the same trick for the same reason.

**Insets are handled in CSS here, natively on Android.** The web view ignores
the safe area and the course's `env(safe-area-inset-*)` rules keep its chrome
clear of the notch and the home indicator. Android does it the other way round,
because there `env()` reports only the display cutout and nothing for the
navigation bar. Both are documented where they are implemented.

## Privacy

The app collects nothing and transmits nothing. It has no network code at all —
the only content it ever loads is a file inside its own bundle, served over a
scheme that resolves to that bundle.

`ITSAppUsesNonExemptEncryption` is declared `false` in `Info.plist`, so the
export-compliance question is answered once instead of on every upload.

## Before submitting to the App Store

- [ ] Change `PRODUCT_BUNDLE_IDENTIFIER` if `com.claudecodeacademy.course` is
      not yours, and register it on the developer portal.
- [ ] Set `DEVELOPMENT_TEAM`, or select the team in Xcode.
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` per upload.
- [ ] App Privacy questionnaire: **Data Not Collected**.
- [ ] Screenshots for 6.7", 6.5" and 5.5" iPhones, plus 12.9" iPad — the app is
      universal, so iPad screenshots are required, not optional.
- [ ] Age rating (educational, no user content).
- [ ] A privacy policy URL. Apple requires one even when nothing is collected.
- [ ] Archive → Validate → Distribute. Validation is where a bad icon or a
      missing plist key is caught, and it is much faster than a review round.
