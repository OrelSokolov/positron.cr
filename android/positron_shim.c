/* positron_shim.c — C seam between the Java shim (PositronActivity) and
 * the Crystal host.
 *
 * Threading contract (the hard rule of this port): the Crystal runtime
 * lives on ONE native thread ("host thread") created here. Native
 * methods are called from Java threads (UI thread, WebView IO threads,
 * the JS bridge thread) and must never touch Crystal. They only:
 *   - cache global refs (nativeInit),
 *   - push plain copied strings onto a mutex-guarded queue, popped by
 *     the host pump (positron_shim_pop),
 *   - block on a condition variable for synchronous asset requests
 *     (positron_shim_asset_*), answered by the host pump.
 *
 * The host boot entry (positron_android_host_main, in Crystal,
 * src/positron/entry/android.cr) is started via pthread_create from
 * nativeInit; it boots the Crystal runtime on that thread (GC.init ->
 * Crystal.init_runtime -> __crystal_main) exactly like egui.cr's
 * android_boot, then runs the host pump.
 */

#include <jni.h>
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

/* Event kinds popped by the host pump. */
#define PS_EVT_MESSAGE 1 /* JS bridge envelope      (a = json)          */
#define PS_EVT_EVENT   2 /* OS event                (a = name, b = json) */
#define PS_EVT_STOP    3 /* activity destroyed: stop the pump           */

struct ps_msg {
  int kind;
  char *a;
  char *b;
  struct ps_msg *next;
};

static pthread_mutex_t g_qmtx = PTHREAD_MUTEX_INITIALIZER;
static struct ps_msg *g_qhead = NULL;
static struct ps_msg *g_qtail = NULL;

static JavaVM *g_vm = NULL;
static jobject g_activity = NULL;
static jobject g_webview = NULL;
static jobject g_bridge = NULL;
static pthread_t g_host_thread;
static volatile int g_host_started = 0;

/* Implemented in Crystal (src/positron/entry/android.cr). */
extern void *positron_android_host_main(void *arg);

jint JNI_OnLoad(JavaVM *vm, void *reserved) {
  (void)reserved;
  g_vm = vm;
  return JNI_VERSION_1_6;
}

static void ps_push(int kind, const char *a, const char *b) {
  struct ps_msg *m = malloc(sizeof(*m));
  if (!m) abort();
  m->kind = kind;
  m->a = a ? strdup(a) : NULL;
  m->b = b ? strdup(b) : NULL;
  m->next = NULL;
  pthread_mutex_lock(&g_qmtx);
  if (g_qtail) g_qtail->next = m; else g_qhead = m;
  g_qtail = m;
  pthread_mutex_unlock(&g_qmtx);
}

/* Pop one pending message. Returns 1 and fills the out params, or 0
 * when the queue is empty. The caller frees a/b and the strings with
 * positron_shim_free. */
int positron_shim_pop(int *kind, char **a, char **b) {
  pthread_mutex_lock(&g_qmtx);
  struct ps_msg *m = g_qhead;
  if (m) {
    g_qhead = m->next;
    if (!g_qhead) g_qtail = NULL;
  }
  pthread_mutex_unlock(&g_qmtx);
  if (!m) return 0;
  *kind = m->kind;
  *a = m->a;
  *b = m->b;
  free(m);
  return 1;
}

void positron_shim_free(void *p) { free(p); }

JavaVM *positron_shim_vm(void) { return g_vm; }
jobject positron_shim_activity(void) { return g_activity; }
jobject positron_shim_webview(void) { return g_webview; }
jobject positron_shim_bridge(void) { return g_bridge; }

/* --- Synchronous asset request (shouldInterceptRequest path) -------
 *
 * The Java WebView thread calls nativeAsset; we register a request,
 * the host pump serves it (positron_shim_asset_take/_done) and the
 * caller wakes up with the bytes. Bounded wait so a sick host turns
 * into a 404 instead of a dead WebView thread. */

struct ps_asset_req {
  pthread_mutex_t m;
  pthread_cond_t c;
  int done;
  char *path;      /* owned by the request */
  uint8_t *data;   /* malloc'd copy, owned by the request */
  size_t len;
  char *mime;      /* malloc'd copy, owned by the request */
};

static struct ps_asset_req *g_asset_req = NULL; /* at most one in flight */
static pthread_mutex_t g_amtx = PTHREAD_MUTEX_INITIALIZER;

/* Host side: return the pending request (or NULL). The request is
 * detached from the registry here; answer it exactly once with
 * positron_shim_asset_done. */
void *positron_shim_asset_take(void) {
  pthread_mutex_lock(&g_amtx);
  struct ps_asset_req *r = g_asset_req;
  g_asset_req = NULL;
  pthread_mutex_unlock(&g_amtx);
  return r;
}

/* Host side: the request path (not copied; valid until _done). */
const char *positron_shim_asset_path(void *req) {
  return ((struct ps_asset_req *)req)->path;
}

/* Host side: copy the response bytes + mime into the request and wake
 * the Java thread. data==NULL / len==0 means "not found". */
void positron_shim_asset_done(void *req, const uint8_t *data, size_t len,
                              const char *mime) {
  struct ps_asset_req *r = req;
  pthread_mutex_lock(&r->m);
  if (data && len) {
    r->data = malloc(len);
    if (!r->data) abort();
    memcpy(r->data, data, len);
    r->len = len;
  }
  r->mime = mime ? strdup(mime) : NULL;
  r->done = 1;
  pthread_cond_signal(&r->c);
  pthread_mutex_unlock(&r->m);
}

static void ps_req_free(struct ps_asset_req *r) {
  free(r->path);
  free(r->data);
  free(r->mime);
  pthread_cond_destroy(&r->c);
  pthread_mutex_destroy(&r->m);
  free(r);
}

/* Bound the synchronous wait: a stalled host must not wedge the
 * WebView's IO threads forever. */
#define PS_ASSET_TIMEOUT_SECONDS 5

/* Perform one blocking asset roundtrip. On return *out_arr holds the
 * bytes (NULL = not found) and *out_mime the malloc'd MIME string
 * (owned by the caller, free with positron_shim_free). */
static void ps_asset_blocking(JNIEnv *env, jstring jpath,
                              jbyteArray *out_arr, char **out_mime) {
  *out_arr = NULL;
  *out_mime = NULL;

  const char *path = (*env)->GetStringUTFChars(env, jpath, NULL);
  if (!path) return;

  struct ps_asset_req *r = malloc(sizeof(*r));
  if (!r) abort();
  pthread_mutex_init(&r->m, NULL);
  pthread_cond_init(&r->c, NULL);
  r->done = 0;
  r->path = strdup(path);
  r->data = NULL;
  r->len = 0;
  r->mime = NULL;
  (*env)->ReleaseStringUTFChars(env, jpath, path);

  pthread_mutex_lock(&g_amtx);
  /* Single-slot registry: a previous unanswered request would leak a
   * waiter, so answer it as "not found" first. */
  if (g_asset_req) {
    positron_shim_asset_done(g_asset_req, NULL, 0, NULL);
    g_asset_req = NULL;
  }
  g_asset_req = r;
  pthread_mutex_unlock(&g_amtx);

  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  ts.tv_sec += PS_ASSET_TIMEOUT_SECONDS;

  pthread_mutex_lock(&r->m);
  while (!r->done) {
    if (pthread_cond_timedwait(&r->c, &r->m, &ts) == ETIMEDOUT) break;
  }
  int have = r->done;
  pthread_mutex_unlock(&r->m);

  if (have) {
    if (r->data && r->len) {
      jbyteArray arr = (*env)->NewByteArray(env, (jsize)r->len);
      if (arr) {
        (*env)->SetByteArrayRegion(env, arr, 0, (jsize)r->len,
                                   (const jbyte *)r->data);
        *out_arr = arr;
      }
    }
    *out_mime = r->mime;
    r->mime = NULL; /* ownership moves to the caller */
  }
  ps_req_free(r);
}

/* --- Native methods (Java threads only; no Crystal here) ----------- */

JNIEXPORT void JNICALL
Java_com_positron_shim_PositronActivity_nativeInit(JNIEnv *env, jobject clazz,
                                                   jobject activity,
                                                   jobject webview,
                                                   jobject bridge) {
  (void)clazz;
  g_activity = (*env)->NewGlobalRef(env, activity);
  g_webview = (*env)->NewGlobalRef(env, webview);
  g_bridge = (*env)->NewGlobalRef(env, bridge);
  if (!g_host_started) {
    g_host_started = 1;
    if (pthread_create(&g_host_thread, NULL, positron_android_host_main,
                       NULL) != 0) {
      abort();
    }
    pthread_detach(g_host_thread);
  }
}

JNIEXPORT void JNICALL
Java_com_positron_shim_PositronActivity_nativePostMessage(JNIEnv *env,
                                                          jobject clazz,
                                                          jstring json) {
  (void)clazz;
  const char *c = (*env)->GetStringUTFChars(env, json, NULL);
  if (!c) return;
  ps_push(PS_EVT_MESSAGE, c, NULL);
  (*env)->ReleaseStringUTFChars(env, json, c);
}

JNIEXPORT void JNICALL
Java_com_positron_shim_PositronActivity_nativeEvent(JNIEnv *env, jobject clazz,
                                                    jstring name,
                                                    jstring payload) {
  (void)clazz;
  const char *n = name ? (*env)->GetStringUTFChars(env, name, NULL) : NULL;
  const char *p =
      payload ? (*env)->GetStringUTFChars(env, payload, NULL) : NULL;
  if (n) {
    ps_push(PS_EVT_EVENT, n, p);
    (*env)->ReleaseStringUTFChars(env, name, n);
  }
  if (p) (*env)->ReleaseStringUTFChars(env, payload, p);
}

JNIEXPORT void JNICALL
Java_com_positron_shim_PositronActivity_nativeStop(JNIEnv *env, jobject clazz) {
  (void)clazz;
  ps_push(PS_EVT_STOP, NULL, NULL);
}

JNIEXPORT jbyteArray JNICALL
Java_com_positron_shim_PositronActivity_nativeAsset(JNIEnv *env, jobject clazz,
                                                    jstring path) {
  (void)clazz;
  jbyteArray arr = NULL;
  char *mime = NULL;
  ps_asset_blocking(env, path, &arr, &mime);
  free(mime);
  return arr;
}

JNIEXPORT jstring JNICALL
Java_com_positron_shim_PositronActivity_nativeAssetMime(JNIEnv *env,
                                                        jobject clazz,
                                                        jstring path) {
  (void)clazz;
  jbyteArray arr = NULL;
  char *mime = NULL;
  ps_asset_blocking(env, path, &arr, &mime);
  if (arr) (*env)->DeleteLocalRef(env, arr);
  jstring result = mime ? (*env)->NewStringUTF(env, mime) : NULL;
  free(mime);
  return result;
}
