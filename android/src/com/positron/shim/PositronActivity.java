// PositronActivity — the whole native UI shim of an Android Positron
// app (positron-architecture.md §7: "Kotlin Shim, 80 строк", minus
// gradle/Kotlin: plain java so javac+d8 suffice, like the perevodilka
// APK pipeline). The Activity is passive: it owns the WebView, forwards
// OS events to the Crystal host through the C shim and executes the
// commands Crystal sends back through PositronBridge. All application
// state and logic live in the Crystal .so (libpositron_android.so).
package com.positron.shim;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;
import android.util.DisplayMetrics;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.ByteArrayInputStream;
import java.util.Locale;

public class PositronActivity extends Activity {
    public static final String ASSET_HOST = "app.positron.local";
    public static final String ASSET_ORIGIN = "https://" + ASSET_HOST + "/";

    private WebView webView;
    private PositronBridge bridge;

    // ==== Native entry points (android/positron_shim.c) ====
    private native void nativeInit(Object activity, Object webView, Object bridge);
    private native void nativePostMessage(String json);
    private native void nativeEvent(String name, String payload);
    private native void nativeStop();
    private native byte[] nativeAsset(String path);
    private native String nativeAssetMime(String path);

    static {
        System.loadLibrary("positron_android");
    }

    // ==== OS entry points ====
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        // Devtools on debuggable builds (POSITRON_DEV analogue).
        if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            WebView.setWebContentsDebuggingEnabled(true);
        }

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return interceptAsset(request.getUrl());
            }

            @SuppressWarnings("deprecation")
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
                return interceptAsset(Uri.parse(url));
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                // Same parity as the desktop adapters: WebView
                // permission requests (getUserMedia, ...) are granted
                // and broadcast; the app can still veto in JS/ Crystal.
                runOnUiThread(new Runnable() {
                    @Override public void run() {
                        request.grant(request.getResources());
                    }
                });
            }
        });

        // The JS bridge object lands in window.PositronBridge before
        // any page loads — exactly the name the Positron JS facade
        // calls (`window.PositronBridge.postMessage(json)`).
        bridge = new PositronBridge();
        webView.addJavascriptInterface(bridge, "PositronBridge");

        setContentView(webView);

        // Hand control to the Crystal host (boots its own thread).
        nativeInit(this, webView, bridge);

        // Cold-start deep link, if any.
        Uri data = getIntent() != null ? getIntent().getData() : null;
        if (data != null) {
            nativeEvent("deep_link", "{\"url\":" + jsonEscape(data.toString()) + "}");
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        nativeEvent("lifecycle", "{\"state\":\"resume\"}");
    }

    @Override
    protected void onPause() {
        super.onPause();
        nativeEvent("lifecycle", "{\"state\":\"pause\"}");
    }

    @Override
    protected void onDestroy() {
        nativeEvent("lifecycle", "{\"state\":\"destroy\"}");
        nativeStop();
        super.onDestroy();
        // The Crystal runtime cannot reboot inside a reused process;
        // keep the lifecycle honest and exit with the Activity.
        if (isFinishing()) {
            System.exit(0);
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        Uri data = intent != null ? intent.getData() : null;
        if (data != null) {
            nativeEvent("deep_link", "{\"url\":" + jsonEscape(data.toString()) + "}");
        }
    }

    @Override
    public void onBackPressed() {
        // Web history first (SPA back navigation), Activity exit after.
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    // Embedded assets are served from the virtual HTTPS host (mobile
    // WebViews reject custom URI schemes — the WebView2 trick).
    private WebResourceResponse interceptAsset(Uri url) {
        if (url == null || !ASSET_HOST.equals(url.getHost())) {
            return null;
        }
        String path = url.getPath();
        byte[] bytes = nativeAsset(path);
        if (bytes == null) {
            return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found",
                    java.util.Collections.<String, String>emptyMap(),
                    new ByteArrayInputStream(new byte[0]));
        }
        String mime = nativeAssetMime(path);
        if (mime == null) {
            mime = "application/octet-stream";
        }
        return new WebResourceResponse(mime, null, new ByteArrayInputStream(bytes));
    }

    static String jsonEscape(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        b.append(String.format(Locale.US, "\\u%04x", (int) c));
                    } else {
                        b.append(c);
                    }
            }
        }
        return b.append('"').toString();
    }

    /**
     * Passive executor: every method here is called FROM Crystal
     * through JNI (adapters/android/jni.cr) or by the WebView bridge,
     * never the other way around. UI work marshals to the UI thread.
     */
    public class PositronBridge {

        // ==== WebView driving (from Crystal) ====

        @JavascriptInterface
        public String postMessage(String json) {
            // JS → Crystal. Async like on desktop: resolves come back
            // through evalJs calling window.__positronResolve.
            nativePostMessage(json);
            return "";
        }

        public void evalJs(final String script) {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    webView.evaluateJavascript(script, null);
                }
            });
        }

        public void loadHtml(final String html, final String baseUrl) {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    webView.loadDataWithBaseURL(baseUrl, html, "text/html", "utf-8", null);
                }
            });
        }

        public void loadUrl(final String url) {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    webView.loadUrl(url);
                }
            });
        }

        public void showWebview() {
            // The WebView is the content view; visibility is managed by
            // the Activity lifecycle.
        }

        public void hideWebview() {
        }

        public void finishApp() {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    finish();
                }
            });
        }

        // ==== Plugin executors (from Crystal) ====

        public boolean writeClipboardText(String text) {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            cm.setPrimaryClip(ClipData.newPlainText("positron", text));
            return true;
        }

        public String readClipboardText() {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            ClipData clip = cm.getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0) return null;
            CharSequence text = clip.getItemAt(0).coerceToText(PositronActivity.this);
            return text != null ? text.toString() : null;
        }

        public boolean clipboardHasText() {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            return cm.hasPrimaryClip() && cm.getPrimaryClipDescription().hasMimeType(
                    "text/plain");
        }

        public String uiTheme() {
            int mask = getResources().getConfiguration().uiMode
                    & Configuration.UI_MODE_NIGHT_MASK;
            return mask == Configuration.UI_MODE_NIGHT_YES ? "dark" : "light";
        }

        public String displayInfo() {
            DisplayMetrics m = getResources().getDisplayMetrics();
            double x = Math.pow(m.widthPixels / m.xdpi, 2);
            double y = Math.pow(m.heightPixels / m.ydpi, 2);
            double diagonal = Math.sqrt(x + y);
            boolean landscape = m.widthPixels > m.heightPixels;
            return "{\"width\":" + m.widthPixels
                    + ",\"height\":" + m.heightPixels
                    + ",\"dpi\":" + m.densityDpi
                    + ",\"scale\":" + m.density
                    + ",\"diagonal\":" + String.format(Locale.US, "%.1f", diagonal)
                    + ",\"orientation\":\"" + (landscape ? "landscape" : "portrait") + "\"}";
        }

        public String prefGet(String key, String defaultValue) {
            SharedPreferences prefs = getSharedPreferences("positron", MODE_PRIVATE);
            return prefs.getString(key, defaultValue);
        }

        public String prefAll() {
            SharedPreferences prefs = getSharedPreferences("positron", MODE_PRIVATE);
            StringBuilder b = new StringBuilder("{");
            boolean first = true;
            for (java.util.Map.Entry<String, ?> e : prefs.getAll().entrySet()) {
                if (!first) b.append(',');
                first = false;
                b.append(jsonEscape(e.getKey())).append(':')
                        .append(jsonEscape(String.valueOf(e.getValue())));
            }
            return b.append('}').toString();
        }

        public boolean prefSet(String key, String value) {
            getSharedPreferences("positron", MODE_PRIVATE)
                    .edit().putString(key, value).apply();
            return true;
        }

        public boolean prefRemove(String key) {
            getSharedPreferences("positron", MODE_PRIVATE).edit().remove(key).apply();
            return true;
        }

        public boolean prefClear() {
            getSharedPreferences("positron", MODE_PRIVATE).edit().clear().apply();
            return true;
        }
    }
}
