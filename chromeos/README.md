# Claude Code Academy — Chromebook

The same course the Windows `.exe` and the Linux binary carry, in the two
shapes a Chromebook can actually take it.

```
chromeos/
  enhance.html            the ChromeOS layer (source)
  pwa/manifest.webmanifest  installed-app metadata (source)
  pwa/sw.js               offline service worker (source)
  build-chromebook.sh     builds both editions
docs/                     the installable build (generated, but tracked)
```

## The two builds

**The file build** — `Claude Code Academy (Chromebook).html`, one file.
Put it in the student's Downloads. They open the **Files** app, double-click
it, and Chrome shows the course. No install, no account, no network, ever.
This is the file to attach to a GitHub release.

**The installable build** — `docs/`, laid out for GitHub Pages. The student
visits the URL once and clicks **Install as an app**. They get an icon in the
shelf, the course in its own window with no tab strip, and a cached copy that
keeps working with the Wi-Fi off.

On ChromeOS the installed web app *is* the native app. There is no `.exe` to
ship, so this is the ChromeOS equivalent of `win/` and `linux/`.

## Build it

```bash
bash ~/claude-code-course/chromeos/build-chromebook.sh
```

It regenerates the desktop build first, so the Chromebook edition can never be
a rebuild behind the course. Needs `python3` and ImageMagick.

## Publish the installable build

Once, after the first build is committed:

**Settings → Pages → Source: Deploy from a branch → `master` / `/docs` → Save**

The course then lives at
`https://natezane1.github.io/claude-code-academy/`, and every later
`git push` of a rebuilt `docs/` updates it.

## What the ChromeOS layer adds

`index.html` is never edited for ChromeOS. `enhance.html` is spliced in before
`</body>` and only covers what a Chromebook has that a desktop browser does not:

| | |
|---|---|
| **Short screens** | 1366x768 is still the common panel. The desktop build scales the page to 1.1, which on 768px of height pushes the nav bar into the slide. Below 850px tall the zoom is handed back. |
| **The hinge** | Folded into a tablet there is no trackpad, so under `pointer: coarse` every control grows to a 48dp target and a horizontal swipe changes slide. |
| **Install** | The button appears only once Chrome fires `beforeinstallprompt`, so it can never promise an install that will not happen. |
| **No network** | The service worker precaches the course on install and serves it cache-first. Verified with the server killed: the page still loads, from the worker. |

Deliberately **no** history seeding. The phone apps push a history entry so an
edge-swipe has something to pop; here the course runs in a real browser tab,
where hijacking Back would trap the student on the page.

The same `enhance.html` is in both builds. It feature-detects rather than
reading a build flag, so the file build silently skips the worker (`file://`
cannot register one) and carries no manifest link.
