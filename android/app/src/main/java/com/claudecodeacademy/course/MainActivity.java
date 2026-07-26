package com.claudecodeacademy.course;

import android.annotation.SuppressLint;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.app.Activity;

/**
 * Claude Code Academy — the whole course, offline, in one WebView.
 *
 * The app declares no permissions at all, INTERNET included. The course is a
 * single self-contained HTML file in assets/ with no external requests, so the
 * app has nothing to ask for. That is also what makes the Play Data Safety
 * form honest and trivial: no data collected, none transmitted, because there
 * is no network stack available to it.
 */
public class MainActivity extends Activity {

    /** file:// rather than a content provider on purpose — see setUpWebView(). */
    private static final String COURSE_URL = "file:///android_asset/course.html";

    private WebView web;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        goEdgeToEdge();

        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#0f1513")); // --paper, so no white flash
        web.setLayoutParams(new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(web);

        applySystemBarInsets(web);
        setUpWebView();

        // Restoring beats reloading: it keeps the current slide and the scroll
        // position across a rotation or a low-memory kill, which is the whole
        // point of holding state in the WebView rather than re-reading assets.
        if (savedInstanceState != null) {
            web.restoreState(savedInstanceState);
        } else {
            web.loadUrl(COURSE_URL);
        }
    }

    /**
     * targetSdk 35 draws every app edge-to-edge and does not let it opt out, so
     * the bars are ours to handle. We pad the WebView by the system bar insets
     * natively instead of leaning on CSS env(safe-area-inset-*): on Android
     * those map to the display cutout only and report nothing for the
     * navigation bar, which would leave the "Next" button underneath it.
     *
     * The CSS layer still declares env() with a 0px fallback, so it resolves to
     * zero here and does the real work on iOS. Neither platform double-counts.
     */
    private void goEdgeToEdge() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            getWindow().setDecorFitsSystemWindows(false);
        } else {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            // Deprecated from API 35, where the bars are always transparent anyway.
            getWindow().setStatusBarColor(Color.TRANSPARENT);
            getWindow().setNavigationBarColor(Color.TRANSPARENT);
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
    }

    private void applySystemBarInsets(final View target) {
        target.setOnApplyWindowInsetsListener((v, insets) -> {
            final int top, bottom, left, right;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                android.graphics.Insets bars = insets.getInsets(
                        WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                top = bars.top; bottom = bars.bottom; left = bars.left; right = bars.right;
            } else {
                top = insets.getSystemWindowInsetTop();
                bottom = insets.getSystemWindowInsetBottom();
                left = insets.getSystemWindowInsetLeft();
                right = insets.getSystemWindowInsetRight();
            }
            v.setPadding(left, top, right, bottom);
            return insets;
        });
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void setUpWebView() {
        WebSettings s = web.getSettings();

        // The course is a JavaScript slide deck; without this it is a blank page.
        s.setJavaScriptEnabled(true);

        // localStorage — this is what remembers which slide you were on and
        // which badges you have earned. Off by default, and the single most
        // common reason a WebView-wrapped course "forgets" everything.
        s.setDomStorageEnabled(true);

        // Read course.html out of the APK. Deliberately NOT paired with
        // setAllowFileAccessFromFileURLs / setAllowUniversalAccessFromFileURLs:
        // the course fetches nothing, so granting a file:// origin the right to
        // read other files would be permission we never spend.
        s.setAllowFileAccess(true);
        s.setAllowContentAccess(false);

        // Respect the reader's system font size. The deck sizes everything in
        // clamp()/vw so it reflows rather than clipping.
        s.setTextZoom(getResources().getConfiguration().fontScale >= 1f
                ? (int) (getResources().getConfiguration().fontScale * 100) : 100);

        // Pinch-to-zoom stays available for accessibility, without the +/- chrome.
        s.setSupportZoom(true);
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(false);

        // No network stack is reachable anyway, but say so explicitly.
        s.setBlockNetworkLoads(true);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String scheme = uri.getScheme();
                // Anything that is not our own asset leaves for a real browser.
                // An in-app WebView is the wrong place to land on the open web,
                // and it keeps the course from ever being navigated away from.
                if ("file".equals(scheme)) return false;
                openExternally(uri);
                return true;
            }
        });
    }

    private void openExternally(Uri uri) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (ActivityNotFoundException ignored) {
            // No browser installed. Staying put is better than crashing.
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        web.saveState(outState);
    }

    /**
     * Back moves one slide, not one app.
     *
     * This asks the deck where it is rather than leaning on WebView history.
     * The obvious implementation — {@code if (web.canGoBack()) web.goBack()} —
     * was tried first and does not work here: the deck changes slides by
     * redrawing in place, so it creates no history entries, and the single
     * entry the page seeds for iOS's edge-swipe gesture is consumed by the
     * first press. Back then closed the course from slide 4 of 138, which
     * reads as losing your place rather than as leaving.
     *
     * evaluateJavascript is asynchronous, so the decision to leave happens in
     * the callback rather than as a return value. Deferring the close by one
     * round trip is invisible at this scale, and it means the deck — not a
     * guess about history — decides whether there is anywhere left to go.
     */
    @Override
    public void onBackPressed() {
        if (web == null) { super.onBackPressed(); return; }

        web.evaluateJavascript(
                "(function(){try{if(typeof st==='object'&&st.i>0){go(st.i-1);return 'moved';}}catch(e){}return 'exit';})()",
                value -> {
                    // evaluateJavascript hands back a JSON string, quotes included.
                    if (!"\"moved\"".equals(value)) {
                        super.onBackPressed();
                    }
                });
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (web != null) web.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            // Detach before destroy, or the WebView leaks the Activity.
            ((ViewGroup) web.getParent()).removeView(web);
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
