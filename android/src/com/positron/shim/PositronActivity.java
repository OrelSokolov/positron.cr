// PositronActivity — the whole native UI shim of an Android Positron
// app (positron-architecture.md §7: "Kotlin Shim, 80 строк", minus
// gradle/Kotlin: plain java so javac+d8 suffice, like the perevodilka
// APK pipeline). The Activity is passive: it owns the WebView, forwards
// OS events to the Crystal host through the C shim and executes the
// commands Crystal sends back through PositronBridge. All application
// state and logic live in the Crystal .so (libpositron_android.so).
package com.positron.shim;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.net.Uri;
import android.os.Build;
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
import android.widget.EditText;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Locale;

public class PositronActivity extends Activity {
    public static final String ASSET_HOST = "app.positron.local";
    public static final String ASSET_ORIGIN = "https://" + ASSET_HOST + "/";

    // SAF request codes carry the AsyncBridge seq (Crystal side) so
    // onActivityResult can address the right continuation.
    private static final int REQ_SAF_BASE = 0x1000;
    private static final int REQ_PERMISSIONS = 2001;
    private static final int SAF_OPEN = 1;
    private static final int SAF_CREATE = 2;
    private static final String NOTIFICATION_CHANNEL = "positron";
    public static final String NOTIFICATION_CLICK_ACTION =
            "com.positron.shim.NOTIFICATION_CLICK";

    private WebView webView;
    private PositronBridge bridge;

    // Staged content for a pending ACTION_CREATE_DOCUMENT roundtrip,
    // keyed by seq — written to the picked URI in onActivityResult.
    private final HashMap<Integer, String> pendingSaveContent = new HashMap<>();

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

        // Notification taps/buttons arrive as broadcasts while this
        // process lives (registered here, not in the manifest — the
        // Crystal host cannot reboot in a reused process anyway).
        IntentFilter clickFilter =
                new IntentFilter(NOTIFICATION_CLICK_ACTION);
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(notificationReceiver, clickFilter,
                    Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(notificationReceiver, clickFilter);
        }

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

    // ==== SAF picker results (ACTION_OPEN/CREATE_DOCUMENT) ====

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode >= REQ_SAF_BASE && requestCode < REQ_PERMISSIONS) {
            handleSafResult(requestCode - REQ_SAF_BASE, resultCode, data);
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    private void handleSafResult(int seq, int resultCode, Intent data) {
        String content = pendingSaveContent.remove(seq);
        Uri uri = (resultCode == RESULT_OK && data != null) ? data.getData() : null;
        if (uri == null) {
            nativeEvent("saf_result", "{\"seq\":" + seq + ",\"canceled\":true}");
            return;
        }
        try {
            if (content != null) {
                // ACTION_CREATE_DOCUMENT: the adapter stages the payload,
                // the OS picked the destination — write it now.
                OutputStream out = getContentResolver().openOutputStream(uri);
                if (out == null) {
                    nativeEvent("saf_result", "{\"seq\":" + seq + ",\"canceled\":true}");
                    return;
                }
                try {
                    out.write(content.getBytes("UTF-8"));
                } finally {
                    out.close();
                }
                nativeEvent("saf_result", "{\"seq\":" + seq
                        + ",\"path\":" + jsonEscape(uri.toString()) + "}");
            } else {
                // ACTION_OPEN_DOCUMENT: copy the pick into the cache dir
                // so the Crystal side gets a plain readable path (the
                // content:// URI itself would not survive File.read).
                File dest = new File(getCacheDir(),
                        "saf-" + seq + "-" + safeFileName(uri));
                InputStream in = getContentResolver().openInputStream(uri);
                if (in == null) {
                    nativeEvent("saf_result", "{\"seq\":" + seq + ",\"canceled\":true}");
                    return;
                }
                try {
                    copyStream(in, new FileOutputStream(dest));
                } finally {
                    in.close();
                }
                nativeEvent("saf_result", "{\"seq\":" + seq
                        + ",\"path\":" + jsonEscape(dest.getAbsolutePath()) + "}");
            }
        } catch (Exception e) {
            nativeEvent("saf_result", "{\"seq\":" + seq
                    + ",\"error\":" + jsonEscape(String.valueOf(e.getMessage())) + "}");
        }
    }

    // ==== Runtime permission results ====

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQ_PERMISSIONS || permissions.length == 0) return;
        String permission = permissions[0];
        boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        // POST_NOTIFICATIONS arrives as the OS name; the frontend knows
        // it as "notifications".
        if (Manifest.permission.POST_NOTIFICATIONS.equals(permission)) {
            permission = "notifications";
        }
        nativeEvent("permission_result", "{\"permission\":"
                + jsonEscape(permission) + ",\"granted\":" + granted + "}");
    }

    // ==== Shared helpers ====

    private final BroadcastReceiver notificationReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String id = intent.getStringExtra("id");
            String action = intent.getStringExtra("action");
            if (id == null) return;
            nativeEvent("notification_click", "{\"id\":" + jsonEscape(id)
                    + (action != null ? ",\"action\":" + jsonEscape(action) : "") + "}");
            // Bring the app forward — the notification tap is an app
            // open, the event above lets the frontend react to it.
            Intent launch = new Intent(context, PositronActivity.class);
            launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            context.startActivity(launch);
        }
    };

    private static String safeFileName(Uri uri) {
        String last = uri.getLastPathSegment();
        if (last == null || last.isEmpty()) return "pick";
        String name = last.replaceAll("[/\\\\:]", "_");
        int dot = name.lastIndexOf('.');
        String base = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        return (base.length() > 32 ? base.substring(0, 32) : base) + ext;
    }

    private static void copyStream(InputStream in, OutputStream out) throws Exception {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        out.close();
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
        // Chromium wants the bare MIME token with the encoding as a
        // separate constructor param — a "type; charset=..." compound is
        // not parsed and the page renders as plain text.
        String encoding = null;
        if (mime == null) {
            mime = "application/octet-stream";
        } else {
            int semi = mime.indexOf(';');
            if (semi >= 0) {
                encoding = mime.substring(semi + 1)
                        .replace("charset=", "").trim();
                mime = mime.substring(0, semi).trim();
            }
        }
        return new WebResourceResponse(mime, encoding, new ByteArrayInputStream(bytes));
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

        // ==== Plugin executors: file pickers, dialogs, notifications,
        // permissions (from Crystal through the JNI bridge). Results of
        // the async ones come back as saf_result / dialog_result /
        // permission_result events. ====

        /**
         * Start a SAF picker roundtrip. kind: 1 = open (the pick is
         * copied into the cache dir, the result path is readable),
         * 2 = create (`content` is staged and written to the picked
         * destination; the result path is the content:// URI).
         */
        public boolean safStart(int seq, int kind, String mime,
                                String defaultName, String content) {
            Intent intent = new Intent(kind == SAF_CREATE
                    ? Intent.ACTION_CREATE_DOCUMENT : Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType(mime == null || mime.isEmpty() ? "*/*" : mime);
            if (kind == SAF_CREATE && defaultName != null && !defaultName.isEmpty()) {
                intent.putExtra(Intent.EXTRA_TITLE, defaultName);
            }
            final Intent finalIntent = intent;
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    if (kind == SAF_CREATE && content != null) {
                        pendingSaveContent.put(seq, content);
                    }
                    try {
                        startActivityForResult(finalIntent, REQ_SAF_BASE + seq);
                    } catch (ActivityNotFoundException e) {
                        pendingSaveContent.remove(seq);
                        nativeEvent("saf_result",
                                "{\"seq\":" + seq + ",\"canceled\":true}");
                    }
                }
            });
            return true;
        }

        // AlertDialog levels: 0 info, 1 warning, 2 error, 3 question.
        public void msgbox(final int level, final String title, final String message) {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    int icon = level == 1 ? android.R.drawable.ic_dialog_alert
                            : android.R.drawable.ic_dialog_info;
                    new AlertDialog.Builder(PositronActivity.this)
                            .setTitle(title)
                            .setMessage(message)
                            .setIcon(icon)
                            .setPositiveButton(android.R.string.ok, null)
                            .show();
                }
            });
        }

        /** Yes/no box; the answer arrives as a dialog_result event. */
        public void confirmAsk(final int seq, final String title, final String message) {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    new AlertDialog.Builder(PositronActivity.this)
                            .setTitle(title)
                            .setMessage(message)
                            .setPositiveButton(android.R.string.yes,
                                    new android.content.DialogInterface.OnClickListener() {
                                        public void onClick(android.content.DialogInterface d, int w) {
                                            nativeEvent("dialog_result",
                                                    "{\"seq\":" + seq + ",\"ok\":true}");
                                        }
                                    })
                            .setNegativeButton(android.R.string.no,
                                    new android.content.DialogInterface.OnClickListener() {
                                        public void onClick(android.content.DialogInterface d, int w) {
                                            nativeEvent("dialog_result",
                                                    "{\"seq\":" + seq + ",\"ok\":false}");
                                        }
                                    })
                            .setOnCancelListener(
                                    new android.content.DialogInterface.OnCancelListener() {
                                        public void onCancel(android.content.DialogInterface d) {
                                            nativeEvent("dialog_result",
                                                    "{\"seq\":" + seq + ",\"ok\":false}");
                                        }
                                    })
                            .show();
                }
            });
        }

        /** Text input box; the answer arrives as a dialog_result event. */
        public void promptAsk(final int seq, final String title, final String message,
                              final String defaultText) {
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    final EditText input = new EditText(PositronActivity.this);
                    input.setText(defaultText);
                    new AlertDialog.Builder(PositronActivity.this)
                            .setTitle(title)
                            .setMessage(message)
                            .setView(input)
                            .setPositiveButton(android.R.string.ok,
                                    new android.content.DialogInterface.OnClickListener() {
                                        public void onClick(android.content.DialogInterface d, int w) {
                                            nativeEvent("dialog_result", "{\"seq\":" + seq
                                                    + ",\"value\":" + jsonEscape(
                                                            input.getText().toString()) + "}");
                                        }
                                    })
                            .setNegativeButton(android.R.string.cancel,
                                    new android.content.DialogInterface.OnClickListener() {
                                        public void onClick(android.content.DialogInterface d, int w) {
                                            nativeEvent("dialog_result",
                                                    "{\"seq\":" + seq + ",\"canceled\":true}");
                                        }
                                    })
                            .show();
                }
            });
        }

        /** Post a notification; actionsJson is [{"id","title"},…]. */
        public boolean notify(final String id, final String title, final String body,
                              final String actionsJson) {
            NotificationManager nm = (NotificationManager)
                    getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return false;
            // API 33+: without POST_NOTIFICATIONS the system drops the
            // notification silently — ask once, never fail the call.
            if (Build.VERSION.SDK_INT >= 33 && !nm.areNotificationsEnabled()) {
                requestNotificationsPermission();
                return false;
            }
            if (Build.VERSION.SDK_INT >= 26
                    && nm.getNotificationChannel(NOTIFICATION_CHANNEL) == null) {
                nm.createNotificationChannel(new NotificationChannel(
                        NOTIFICATION_CHANNEL, "Positron",
                        NotificationManager.IMPORTANCE_DEFAULT));
            }
            int icon = getApplicationInfo().icon;
            int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
            Intent click = new Intent(NOTIFICATION_CLICK_ACTION);
            click.setPackage(getPackageName());
            click.putExtra("id", id);
            PendingIntent clickPi = PendingIntent.getBroadcast(
                    PositronActivity.this, id.hashCode(), click, flags);

            Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                    ? new Notification.Builder(PositronActivity.this, NOTIFICATION_CHANNEL)
                    : new Notification.Builder(PositronActivity.this);
            builder.setSmallIcon(icon)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setAutoCancel(true)
                    .setContentIntent(clickPi);
            if (actionsJson != null && !actionsJson.isEmpty()) {
                try {
                    org.json.JSONArray actions = new org.json.JSONArray(actionsJson);
                    for (int i = 0; i < actions.length(); i++) {
                        org.json.JSONObject a = actions.getJSONObject(i);
                        String actionId = a.optString("id", "");
                        String label = a.optString("title", "");
                        if (actionId.isEmpty() || label.isEmpty()) continue;
                        Intent ai = new Intent(NOTIFICATION_CLICK_ACTION);
                        ai.setPackage(getPackageName());
                        ai.putExtra("id", id);
                        ai.putExtra("action", actionId);
                        PendingIntent pi = PendingIntent.getBroadcast(
                                PositronActivity.this,
                                (id + "#" + actionId).hashCode(), ai, flags);
                        builder.addAction(new Notification.Action.Builder(
                                icon, label, pi).build());
                    }
                } catch (org.json.JSONException e) {
                    // Malformed actions — post without buttons.
                }
            }
            nm.notify(id, 0, builder.build());
            return true;
        }

        public boolean clearNotification(String id) {
            NotificationManager nm = (NotificationManager)
                    getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return false;
            nm.cancel(id, 0);
            return true;
        }

        public boolean notificationsEnabled() {
            NotificationManager nm = (NotificationManager)
                    getSystemService(Context.NOTIFICATION_SERVICE);
            return nm != null && nm.areNotificationsEnabled();
        }

        /** Ask for POST_NOTIFICATIONS (API 33+); result event follows. */
        public boolean requestNotificationsPermission() {
            if (Build.VERSION.SDK_INT < 33) return true;
            NotificationManager nm = (NotificationManager)
                    getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null && nm.areNotificationsEnabled()) return true;
            return requestOsPermission("notifications");
        }

        // Map frontend permission names to OS permissions. Returns null
        // for names that need no runtime permission ("clipboard",
        // "files" — SAF needs none) and "" for unsupported ones.
        private String osPermissionFor(String name) {
            if (name == null) return "";
            if (name.equals("camera")) return Manifest.permission.CAMERA;
            if (name.equals("microphone")) return Manifest.permission.RECORD_AUDIO;
            if (name.equals("location")) return Manifest.permission.ACCESS_FINE_LOCATION;
            if (name.equals("notifications")) return Manifest.permission.POST_NOTIFICATIONS;
            if (name.equals("clipboard") || name.equals("files")) return null;
            return "";
        }

        /** "granted" | "prompt" | "denied" for a frontend permission name. */
        public String checkOsPermission(String name) {
            if (name != null && name.equals("notifications")) {
                NotificationManager nm = (NotificationManager)
                        getSystemService(Context.NOTIFICATION_SERVICE);
                boolean enabled = nm == null || Build.VERSION.SDK_INT < 33
                        || nm.areNotificationsEnabled();
                return enabled ? "granted" : "prompt";
            }
            String perm = osPermissionFor(name);
            if (perm == null) return "granted";
            if (perm.isEmpty()) return "denied";
            int state = checkSelfPermission(perm);
            return state == PackageManager.PERMISSION_GRANTED ? "granted" : "prompt";
        }

        /** Fire the OS permission dialog; result event follows. */
        public boolean requestOsPermission(final String name) {
            String state = checkOsPermission(name);
            if (!state.equals("prompt")) return state.equals("granted");
            final String perm = osPermissionFor(name);
            if (perm == null || perm.isEmpty()) return false;
            runOnUiThread(new Runnable() {
                @Override public void run() {
                    // Activity#requestPermissions (API 23+) — no
                    // androidx in this pipeline.
                    requestPermissions(new String[]{perm}, REQ_PERMISSIONS);
                }
            });
            return false;
        }
    }
}
