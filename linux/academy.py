#!/usr/bin/env python3
"""
Claude Code Academy — Linux app.

A real application window: GTK frame, WebKit inside it. No tabs, no address
bar, no browser. The course itself (one self-contained HTML file, no network)
is appended to this script by build-linux-app.sh, so the built app is a single
file you can send to someone.

Run the built app, or run this file directly during development — with no
payload appended it falls back to ../claude-code-academy.html.
"""

import base64
import gzip
import os
import sys
from pathlib import Path

APP_NAME = "Claude Code Academy"
APP_ID = "claude-code-academy"
WINDOW_SIZE = (1280, 860)
ZOOM_LIMITS = (0.5, 2.5)
ZOOM_STEP = 0.1

# Progress lives in the webview's localStorage, so the data directory has to be
# stable across runs — it is the difference between the course remembering your
# badges and forgetting them every launch.
DATA_DIR = Path(
    os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")
) / "ClaudeCodeAcademy"

# build-linux-app.sh appends the course and the icon after these markers, each
# as one long base64 line. Split so neither marker matches this source itself.
HTML_MARKER = "#---COURSE" + "-HTML---"
ICON_MARKER = "#---COURSE" + "-ICON---"


def read_section(marker):
    """Pull one gzipped, base64'd payload out of the tail of this file."""
    try:
        lines = Path(__file__).read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None

    for i, line in enumerate(lines):
        if line.strip() == marker and i + 1 < len(lines):
            blob = lines[i + 1].lstrip("#").strip()
            try:
                return gzip.decompress(base64.b64decode(blob))
            except (ValueError, OSError):
                return None
    return None


def course_html():
    """The course, from the appended payload or from the dev source next door."""
    payload = read_section(HTML_MARKER)
    if payload is not None:
        return payload

    fallback = Path(__file__).resolve().parent.parent / "claude-code-academy.html"
    if fallback.is_file():
        return fallback.read_bytes()

    sys.exit(f"error: no course payload, and {fallback} is missing")


def unpack(html):
    """Put the course on disk so it loads under a stable file:// origin."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    target = DATA_DIR / "claude-code-academy.html"

    # Always rewrite rather than trying to detect "same build". Comparing sizes
    # was cheaper but wrong: two builds of the course can land on the same byte
    # count, and the failure mode is the app silently serving a stale copy
    # forever. This is 150 KB to a local file, once, at launch.
    target.write_bytes(html)
    return target


def open_in_browser(path):
    """Last resort when GTK or WebKit is unavailable: at least show the course."""
    import subprocess

    sys.stderr.write(
        f"{APP_NAME}: GTK/WebKit not available, falling back to your browser.\n"
        "For the real app window, install:\n"
        "  sudo apt install python3-gi gir1.2-webkit2-4.1 gir1.2-gtk-3.0\n"
    )
    try:
        subprocess.Popen(["xdg-open", str(path)])
    except OSError:
        sys.exit(f"error: could not open {path}")


def main():
    html = course_html()
    page = unpack(html)

    try:
        import gi

        # Every namespace needs pinning, not just Gtk: GTK 4 is installed too,
        # and an unpinned Gdk resolves to 4.0 and then refuses to sit next to
        # Gtk 3.0 — which looks exactly like "WebKit is not installed".
        gi.require_version("Gtk", "3.0")
        gi.require_version("Gdk", "3.0")
        gi.require_version("GdkPixbuf", "2.0")
        gi.require_version("WebKit2", "4.1")
        from gi.repository import Gdk, GdkPixbuf, Gio, GLib, Gtk, WebKit2
    except (ImportError, ValueError):
        open_in_browser(page)
        return

    # Wayland and GNOME match a window to its .desktop file by this name; without
    # it the app shows up as a generic unnamed window with no icon.
    GLib.set_prgname(APP_ID)
    GLib.set_application_name(APP_NAME)

    # Keep cookies, caches and localStorage under our own directory rather than
    # leaking into the user's default WebKit profile.
    manager = WebKit2.WebsiteDataManager(
        base_data_directory=str(DATA_DIR / "webkit"),
        base_cache_directory=str(DATA_DIR / "webkit-cache"),
    )
    context = WebKit2.WebContext.new_with_website_data_manager(manager)
    context.set_cache_model(WebKit2.CacheModel.DOCUMENT_VIEWER)

    view = WebKit2.WebView(web_context=context)
    settings = view.get_settings()
    settings.set_enable_developer_extras(False)
    settings.set_enable_write_console_messages_to_stdout(False)
    settings.set_javascript_can_open_windows_automatically(False)
    settings.set_enable_back_forward_navigation_gestures(True)

    window = Gtk.Window(title=APP_NAME)
    window.set_default_size(*WINDOW_SIZE)
    window.set_position(Gtk.WindowPosition.CENTER)
    window.add(view)
    window.connect("destroy", Gtk.main_quit)

    icon = read_section(ICON_MARKER)
    if icon:
        loader = GdkPixbuf.PixbufLoader.new_with_type("png")
        try:
            loader.write(icon)
            loader.close()
            window.set_icon(loader.get_pixbuf())
        except GLib.Error:
            pass

    def on_navigate(_view, decision, decision_type):
        """The course is entirely local. Anything off-site belongs in a browser."""
        kinds = WebKit2.PolicyDecisionType
        if decision_type not in (kinds.NAVIGATION_ACTION, kinds.NEW_WINDOW_ACTION):
            return False

        uri = decision.get_navigation_action().get_request().get_uri()
        if uri.startswith(("http://", "https://", "mailto:")):
            decision.ignore()
            Gio.AppInfo.launch_default_for_uri(uri, None)
            return True

        if decision_type is kinds.NEW_WINDOW_ACTION:
            decision.ignore()
            view.load_uri(uri)
            return True

        return False

    view.connect("decide-policy", on_navigate)

    def on_key(_window, event):
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        key = Gdk.keyval_name(event.keyval)

        if key == "F11":
            fullscreen = window.get_window().get_state() & Gdk.WindowState.FULLSCREEN
            window.unfullscreen() if fullscreen else window.fullscreen()
            return True
        if not ctrl:
            return False
        if key in ("q", "w"):
            Gtk.main_quit()
            return True
        if key in ("plus", "equal", "KP_Add"):
            view.set_zoom_level(min(ZOOM_LIMITS[1], view.get_zoom_level() + ZOOM_STEP))
            return True
        if key in ("minus", "KP_Subtract"):
            view.set_zoom_level(max(ZOOM_LIMITS[0], view.get_zoom_level() - ZOOM_STEP))
            return True
        if key in ("0", "KP_0"):
            view.set_zoom_level(1.0)
            return True
        return False

    window.connect("key-press-event", on_key)

    view.load_uri(page.as_uri())
    window.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
