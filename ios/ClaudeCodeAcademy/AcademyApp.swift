import SwiftUI

/// Claude Code Academy — the whole course, offline, in one WKWebView.
///
/// The app makes no network requests and declares no capabilities. The course
/// is a single self-contained HTML file in the bundle, which is what lets the
/// App Privacy card read "Data Not Collected" truthfully rather than as an
/// intention.
@main
struct AcademyApp: App {
    var body: some Scene {
        WindowGroup {
            CourseView()
                // The deck draws its own background edge to edge, and the CSS
                // keeps its chrome clear of the notch and the home indicator
                // with env(safe-area-inset-*). Letting SwiftUI inset the web
                // view as well would band the screen in --paper twice.
                .ignoresSafeArea()
                // The course has no light palette — dark is :root in its CSS,
                // light is an explicit opt-in that this app never sets. Forcing
                // the scheme keeps the status bar legible against it.
                .preferredColorScheme(.dark)
        }
    }
}
