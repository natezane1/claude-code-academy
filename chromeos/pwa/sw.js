/* Claude Code Academy — offline service worker.
 *
 * Generated into docs/ by chromeos/build-chromebook.sh, which substitutes
 * __CCA_VERSION__ with a hash of the built course. A new course build is
 * therefore a new cache name, which is what evicts the old one.
 *
 * The whole "app" is four files and no API, so the strategy is the simple
 * one that actually suits it: precache everything on install, serve from
 * cache, and refresh the copy in the background when there is a network.
 */
"use strict";

const CACHE = "cca-__CCA_VERSION__";

/* Relative to the service worker's own scope, so this works whether the site
   is served from a domain root or from a /repo-name/ project page. */
const SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    /* addAll is all-or-nothing: one 404 and the worker never installs, which
       would leave the student with no offline copy and no error they can see.
       Add them one at a time and let a missing extra be survivable. */
    await Promise.all(SHELL.map((url) => cache.add(url).catch(() => {})));
    /* The course is self-contained, so there is no half-updated state to
       fear — take over as soon as the new files are in. */
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(
      names.filter((n) => n.startsWith("cca-") && n !== CACHE).map((n) => caches.delete(n))
    );
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const req = event.request;

  /* Never touch anything but our own same-origin GETs. */
  if (req.method !== "GET") return;
  if (new URL(req.url).origin !== self.location.origin) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(req, { ignoreSearch: true });

    /* Cache first: a lesson must open instantly and must open on a bus. */
    if (hit) {
      /* Refresh in the background so the next launch has the newer build.
         Deliberately not awaited — the student already has their page. */
      event.waitUntil(
        fetch(req).then((res) => (res && res.ok ? cache.put(req, res.clone()) : null)).catch(() => {})
      );
      return hit;
    }

    try {
      const res = await fetch(req);
      if (res && res.ok) cache.put(req, res.clone());
      return res;
    } catch (_) {
      /* Offline and not cached. For a navigation that means a deep link we
         have never seen; the course is one page, so hand back that page. */
      if (req.mode === "navigate") {
        const shell = await cache.match("./index.html");
        if (shell) return shell;
      }
      return new Response("Offline, and this file was never cached.", {
        status: 503,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }
  })());
});
