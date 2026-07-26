# Claude Code Academy — Android

The whole 138-slide course as a native Android app. Offline, no permissions,
no account, no network code.

```
android/
  app/src/main/
    java/com/claudecodeacademy/course/MainActivity.java   the entire app
    assets/course.html                                    the course (generated)
    res/                                                  icons, theme, backup rules
    AndroidManifest.xml
  app/build.gradle.kts                                    versions, signing, R8
  build-apk.sh                                            build without Android Studio
```

## Build it

**In Android Studio:** open the `android/` folder and press Run. Nothing else
to configure.

**On the command line:**

```bash
bash ~/claude-code-course/build-mobile.sh     # refresh the course first
cd ~/claude-code-course/android
./gradlew assembleDebug                       # app/build/outputs/apk/debug/
```

For a release build, point four environment variables at your keystore. They
are read in `app/build.gradle.kts`, so no key material is ever committed:

```bash
export ACADEMY_KEYSTORE=/path/to/release.keystore
export ACADEMY_KEYSTORE_PASSWORD=...
export ACADEMY_KEY_ALIAS=...
export ACADEMY_KEY_PASSWORD=...
./gradlew assembleRelease bundleRelease
```

`bundleRelease` produces the `.aab` that Google Play requires for new apps.
The `.apk` is for sideloading and for testing.

**Whenever you edit the course**, re-run `build-mobile.sh` before building.
The app ships a *copy* of the course inside the APK; without that step you
build the previous version and nothing tells you.

## How it is put together

One `Activity` holding one `WebView`. That is the whole app — there is no
AndroidX dependency, no support library, no Compose. The APK is about 300 KB
over the size of the course itself, and it builds from the platform SDK alone.

Three decisions are worth knowing about, because each of them is a bug if you
get it wrong and silent if you do not test for it:

**`setDomStorageEnabled(true)`.** This is what makes `localStorage` work, and
`localStorage` is where the course keeps your place and your badges. It is off
by default in a `WebView`. Turn it off and the app still runs perfectly — it
just forgets everything every time you close it, which is the single most
common bug in WebView-wrapped courses.

**Insets are applied natively, not in CSS.** `targetSdk 35` draws every app
edge-to-edge with no opt-out. On Android, `env(safe-area-inset-*)` only ever
reports the display cutout and returns zero for the navigation bar, so a deck
that trusted CSS would put its "Next" button underneath the system bar. So
`MainActivity` pads the WebView by the real insets and the CSS `env()` values
resolve to their `0px` fallback. On iOS it is the other way round. Neither
platform double-counts.

**`enableOnBackInvokedCallback` is deliberately off.** Opting in to predictive
back on API 33+ stops `onBackPressed()` being called, and `onBackPressed()` is
what walks the reader back one slide instead of closing the course. If you ever
turn it on, port the back handling to `OnBackInvokedCallback` in the same
commit.

## Permissions

There are none. Not even `INTERNET`.

The course is one self-contained HTML file with no external requests, so the
app has nothing to ask for. That also makes the Play Console **Data Safety**
form trivial and provably honest: no data collected, no data shared, no data
transmitted — there is no network stack available to it.

## Before submitting to Google Play

Everything below is a human decision, not something a build can do for you:

- [ ] Change `applicationId` if `com.claudecodeacademy.course` is not yours.
      It is permanent once published.
- [ ] Generate your own upload keystore and enrol in Play App Signing. Losing
      the upload key means never updating the app again.
- [ ] Bump `versionCode` for every upload. Play rejects a duplicate.
- [ ] Upload the `.aab`, not the `.apk`.
- [ ] Fill in the Data Safety form: *no data collected*.
- [ ] Set the content rating (this is an educational app with no user content).
- [ ] Provide a privacy policy URL. Play requires one even when nothing is
      collected.
- [ ] Screenshots: at least two phone screenshots, plus a 512×512 icon and a
      1024×500 feature graphic.

## Testing it without a device

The build was verified on a headless emulator:

```bash
$ANDROID_HOME/emulator/emulator -avd <name> -no-window -gpu swiftshader_indirect
adb install -r app/build/outputs/apk/release/app-release.apk
adb shell am start -n com.claudecodeacademy.course/.MainActivity
adb exec-out screencap -p > shot.png
```
