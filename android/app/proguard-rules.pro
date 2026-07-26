# The app is one Activity and a WebView, so there is very little for R8 to do.
# These rules exist to stop it doing the two things that would break it.

# The Activity is named in AndroidManifest.xml as a string, not referenced from
# Java, so R8 cannot see that it is used. Without this the launcher entry point
# is stripped and the app installs but will not start.
-keep class com.claudecodeacademy.course.MainActivity { *; }

# WebView JavaScript bridges are called by name from JS. This app ships no
# @JavascriptInterface today, but keeping the rule means adding one later does
# not silently stop working in release builds only — the classic "works in
# debug, blank in release" WebView bug.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep line numbers so a Play Console crash report is readable, while still
# renaming everything else.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
