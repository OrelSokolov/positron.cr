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
#include <android/log.h>

/* Host-thread logging: the Crystal host's stdout/stderr go to /dev/null
 * on Android, so the boot entry reports through the system log (read
 * with `adb logcat -s positron`). */
void positron_shim_log(const char *msg) {
  __android_log_print(ANDROID_LOG_INFO, "positron", "%s", msg);
}

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

/* Host-thread entry: attach the thread HERE, before the Crystal
 * runtime boots. A FRESH AttachCurrentThread issued from inside the
 * booted Crystal runtime kills the process with a clean exit(11)
 * (root cause unknown; the identical C call from the same thread
 * succeeds and Crystal's idempotent re-attach works fine) — the
 * canonical NDK pattern of attaching in the thread's creator sidesteps
 * it entirely: the Crystal side only ever re-attaches. */
/* Host-thread entry: attach the thread HERE, before the Crystal
 * runtime boots. A fresh AttachCurrentThread issued from inside the
 * booted Crystal runtime fails (the raised error then dies inside
 * libunwind's backtrace capture, killing the process) — the canonical
 * NDK pattern of attaching in the thread's creator sidesteps it: the
 * Crystal side only ever re-attaches idempotently. */
static void *ps_host_thread(void *arg) {
  JNIEnv *env = NULL;
  jint attached = (*g_vm)->AttachCurrentThread(g_vm, &env, NULL) == 0;
  __android_log_print(ANDROID_LOG_INFO, "positron",
                      "host: thread attached=%d", attached);
  void *result = positron_android_host_main(arg);
  if (attached) (*g_vm)->DetachCurrentThread(g_vm);
  return result;
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

const struct JNIInvokeInterface *positron_shim_vm(void) {
  /* Return the INVOKE TABLE, not the JavaVM* JNI_OnLoad handed out:
   * the Crystal side's JavaVM alias is the C-mode typedef
   * (`const struct JNIInvokeInterface*`), while g_vm here is a
   * `JavaVM*` — a pointer TO the table pointer (the C++-mode
   * _JavaVM struct whose first field is the table).
   */
  return *g_vm;
}
jobject positron_shim_activity(void) { return g_activity; }

/* --- JNIEnv access: C-seam trampolines ---------------------------------
 * The Crystal side never dereferences the JNI function tables: indirect
 * calls through table slots from cross-compiled Crystal segfault on
 * this platform (identical C calls work — see jni.cr's header), so the
 * seam owns every JNIEnv access. The host thread is attached by
 * ps_host_thread before the Crystal runtime boots, so ps_env() always
 * succeeds there. */
static JNIEnv *ps_env(void) {
  JNIEnv *env = NULL;
  if ((*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK)
    return NULL;
  return env;
}

int positron_jni_attached(void) { return ps_env() != NULL; }

jstring positron_jni_new_string_utf(const char *s) {
  JNIEnv *e = ps_env();
  return e ? (*e)->NewStringUTF(e, s) : NULL;
}

/* Returns a malloc'd copy (free with positron_shim_free). */
char *positron_jni_string_utf(jstring s) {
  JNIEnv *e = ps_env();
  if (!e) return NULL;
  const char *c = (*e)->GetStringUTFChars(e, s, NULL);
  if (!c) return NULL;
  char *copy = strdup(c);
  (*e)->ReleaseStringUTFChars(e, s, c);
  return copy;
}

int positron_jni_exception_check(void) {
  JNIEnv *e = ps_env();
  return e ? (*e)->ExceptionCheck(e) : 0;
}
void positron_jni_exception_describe(void) {
  JNIEnv *e = ps_env();
  if (e) (*e)->ExceptionDescribe(e);
}
void positron_jni_exception_clear(void) {
  JNIEnv *e = ps_env();
  if (e) (*e)->ExceptionClear(e);
}

jclass positron_jni_get_object_class(jobject obj) {
  JNIEnv *e = ps_env();
  return e ? (*e)->GetObjectClass(e, obj) : NULL;
}
jmethodID positron_jni_get_method_id(jobject obj, const char *name,
                                     const char *sig) {
  JNIEnv *e = ps_env();
  if (!e) return NULL;
  jclass cls = (*e)->GetObjectClass(e, obj);
  return cls ? (*e)->GetMethodID(e, cls, name, sig) : NULL;
}

void positron_jni_call_void_a(jobject obj, jmethodID mid, const jlong *args) {
  JNIEnv *e = ps_env();
  if (e) (*e)->CallVoidMethodA(e, obj, mid, (const jvalue *)args);
}
jobject positron_jni_call_object_a(jobject obj, jmethodID mid,
                                   const jlong *args) {
  JNIEnv *e = ps_env();
  return e ? (*e)->CallObjectMethodA(e, obj, mid, (const jvalue *)args) : NULL;
}
jboolean positron_jni_call_boolean_a(jobject obj, jmethodID mid,
                                     const jlong *args) {
  JNIEnv *e = ps_env();
  return e ? (*e)->CallBooleanMethodA(e, obj, mid, (const jvalue *)args) : 0;
}
jint positron_jni_call_int_a(jobject obj, jmethodID mid, const jlong *args) {
  JNIEnv *e = ps_env();
  return e ? (*e)->CallIntMethodA(e, obj, mid, (const jvalue *)args) : 0;
}

jbyteArray positron_jni_new_byte_array(const uint8_t *bytes, jint len) {
  JNIEnv *e = ps_env();
  if (!e) return NULL;
  jbyteArray arr = (*e)->NewByteArray(e, len);
  if (!arr) return NULL;
  (*e)->SetByteArrayRegion(e, arr, 0, len, (const jbyte *)bytes);
  return arr;
}
jint positron_jni_array_length(jarray arr) {
  JNIEnv *e = ps_env();
  return e ? (*e)->GetArrayLength(e, arr) : 0;
}
jboolean positron_jni_get_byte_array(jbyteArray arr, uint8_t *out, jint len) {
  JNIEnv *e = ps_env();
  if (!e) return 0;
  (*e)->GetByteArrayRegion(e, arr, 0, len, (jbyte *)out);
  return 1;
}
void positron_jni_delete_local_ref(jobject obj) {
  JNIEnv *e = ps_env();
  if (e) (*e)->DeleteLocalRef(e, obj);
}
jobject positron_shim_webview(void) { return g_webview; }
jobject positron_shim_bridge(void) { return g_bridge; }

/* --- Synchronous asset request (shouldInterceptRequest path) -------
 *
 * The Java WebView thread calls nativeAsset; we register a request,
 * the host pump serves it (positron_shim_asset_take/_done) and the
 * caller wakes up with the bytes. Bounded wait so a sick host turns
 * into a 404 instead of a dead WebView thread.
 *
 * Chromium fires shouldInterceptRequest for html/css/js/favicon
 * concurrently from several IO threads (and the Java side makes two
 * roundtrips per URL: bytes + mime), so pending requests form a FIFO
 * queue — a single-slot registry would answer still-pending waiters
 * as "not found" whenever a new request registers. */

struct ps_asset_req {
  pthread_mutex_t m;
  pthread_cond_t c;
  int done;
  char *path;      /* owned by the request */
  uint8_t *data;   /* malloc'd copy, owned by the request */
  size_t len;
  char *mime;      /* malloc'd copy, owned by the request */
  struct ps_asset_req *next;
};

static struct ps_asset_req *g_asset_head = NULL;
static struct ps_asset_req *g_asset_tail = NULL;
static pthread_mutex_t g_amtx = PTHREAD_MUTEX_INITIALIZER;

/* Host side: return the oldest pending request (or NULL). The request
 * is detached from the queue here; answer it exactly once with
 * positron_shim_asset_done. */
void *positron_shim_asset_take(void) {
  pthread_mutex_lock(&g_amtx);
  struct ps_asset_req *r = g_asset_head;
  if (r) {
    g_asset_head = r->next;
    if (!g_asset_head) g_asset_tail = NULL;
    r->next = NULL;
  }
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
  /* FIFO append — concurrent WebView IO threads each keep their own
   * pending request; the host pump pops one per tick. */
  r->next = NULL;
  if (g_asset_tail) g_asset_tail->next = r;
  else g_asset_head = r;
  g_asset_tail = r;
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
    if (pthread_create(&g_host_thread, NULL, ps_host_thread,
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

/* --- Camera capture (camera2 NDK; plugins/camera/android.cr) ---------
 *
 * Host-side native capture for the camera plugin, driven ONLY from the
 * Crystal host thread (devices/open/frame/close are plain C calls —
 * no JNIEnv, no Java). An AImageReader surface is the capture target;
 * frames are pulled with acquireLatestImage on latest_frame (called
 * from the app's scheme handler on the host thread) and converted
 * YUV_420_888 -> RGBA in place, rotated/mirrored per the sensor
 * characteristics so a phone's landscape sensor comes out upright in
 * portrait. The device state callbacks run on a camera2-internal
 * thread and only touch C state below — never Crystal.
 *
 * Runtime permission is NOT handled here: the Crystal adapter checks
 * and requests it through the permissions plugin's PositronBridge
 * methods before opening the device.
 *
 * Same shape as the egui.cr camera seam (backend/sokol_shim.c), which
 * is proven on hardware. */
#include <camera/NdkCameraManager.h>
#include <camera/NdkCameraDevice.h>
#include <camera/NdkCameraMetadata.h>
#include <media/NdkImageReader.h>
#include <stdio.h>

static char ps_cam_err[256] = "";
static ACameraManager *ps_cam_mgr = NULL; /* process-wide, on demand */

#define PS_CAM_MAX 8
static char ps_cam_ids[PS_CAM_MAX][64];
static char ps_cam_names[PS_CAM_MAX][96];
static int ps_cam_facing[PS_CAM_MAX];

void positron_cam_close(void *sp);

int positron_cam_devices(void) {
  if (!ps_cam_mgr) ps_cam_mgr = ACameraManager_create();
  if (!ps_cam_mgr) return 0;
  ACameraIdList *ids = NULL;
  if (ACameraManager_getCameraIdList(ps_cam_mgr, &ids) != ACAMERA_OK || !ids)
    return 0;
  int n = 0;
  for (int i = 0; i < ids->numCameras && n < PS_CAM_MAX; i++) {
    const char *id = ids->cameraIds[i];
    int facing = 0; /* 0 unknown/external / 1 front / 2 back */
    ACameraMetadata *chars = NULL;
    if (ACameraManager_getCameraCharacteristics(ps_cam_mgr, id, &chars) ==
            ACAMERA_OK &&
        chars) {
      ACameraMetadata_const_entry e;
      if (ACameraMetadata_getConstEntry(chars, ACAMERA_LENS_FACING, &e) ==
              ACAMERA_OK &&
          e.count > 0)
        facing = e.data.u8[0] == ACAMERA_LENS_FACING_FRONT
                     ? 1
                     : (e.data.u8[0] == ACAMERA_LENS_FACING_BACK ? 2 : 0);
      ACameraMetadata_free(chars);
    }
    strncpy(ps_cam_ids[n], id, 63);
    snprintf(ps_cam_names[n], sizeof(ps_cam_names[n]), "Camera %s (%s)", id,
             facing == 1 ? "front" : (facing == 2 ? "back" : "external"));
    ps_cam_facing[n] = facing;
    n++;
  }
  ACameraManager_deleteCameraIdList(ids);
  return n;
}

const char *positron_cam_dev_id(int i) { return ps_cam_ids[i]; }
const char *positron_cam_dev_name(int i) { return ps_cam_names[i]; }

static void ps_cam_on_disconnect(void *ctx, ACameraDevice *dev) {
  (void)ctx;
  /* The device is gone (served by another client, forced disconnect);
   * close our handle so the session teardown in _close is a no-op there.
   */
  ACameraDevice_close(dev);
}

static void ps_cam_on_error(void *ctx, ACameraDevice *dev, int code) {
  (void)dev;
  if (ctx)
    snprintf(ps_cam_err, sizeof(ps_cam_err), "camera error %d", code);
}

struct ps_cam {
  ACameraDevice *dev;
  ACaptureSessionOutputContainer *outputs;
  ACaptureSessionOutput *soutput;
  ACameraOutputTarget *target;
  ACaptureRequest *req;
  ACameraCaptureSession *session;
  AImageReader *reader;
  ANativeWindow *win;
  uint8_t *rgba;
  int w, h;
  /* ACAMERA_SENSOR_ORIENTATION (0/90/180/270 clockwise) applied in the
   * YUV->RGBA convert — a phone's sensor is landscape while the device
   * is naturally portrait, so an unrotated frame comes out sideways.
   * Front cameras additionally get mirrored (the conventional preview
   * behaviour). */
  int rot;
  int mirror;
};

void *positron_cam_open(const char *devid, int w, int h) {
  ps_cam_err[0] = 0;
  if (!ps_cam_mgr) ps_cam_mgr = ACameraManager_create();
  if (!ps_cam_mgr) {
    snprintf(ps_cam_err, sizeof(ps_cam_err), "no camera manager");
    return NULL;
  }
  /* default: the first BACK-facing camera (the natural phone choice) */
  const char *id = (devid && devid[0]) ? devid : NULL;
  if (!id) {
    int n = positron_cam_devices();
    for (int i = 0; i < n; i++)
      if (ps_cam_facing[i] == 2 || i == n - 1) {
        id = ps_cam_ids[i];
        break;
      }
  }
  if (!id) {
    snprintf(ps_cam_err, sizeof(ps_cam_err), "no camera device");
    return NULL;
  }

  struct ps_cam *s = calloc(1, sizeof(*s));
  ACameraMetadata *chars = NULL;
  if (ACameraManager_getCameraCharacteristics(ps_cam_mgr, id, &chars) ==
          ACAMERA_OK &&
      chars) {
    ACameraMetadata_const_entry e;
    if (ACameraMetadata_getConstEntry(chars, ACAMERA_SENSOR_ORIENTATION,
                                      &e) == ACAMERA_OK &&
        e.count > 0) {
      int r = e.data.i32[0] % 360;
      if (r < 0) r += 360;
      s->rot = (r / 90) * 90; /* 0 / 90 / 180 / 270 */
    }
    if (ACameraMetadata_getConstEntry(chars, ACAMERA_LENS_FACING, &e) ==
            ACAMERA_OK &&
        e.count > 0)
      s->mirror = (e.data.u8[0] == ACAMERA_LENS_FACING_FRONT);
    ACameraMetadata_free(chars);
  }
  ACameraDevice_StateCallbacks dev_cbs;
  memset(&dev_cbs, 0, sizeof(dev_cbs));
  dev_cbs.context = s;
  dev_cbs.onDisconnected = ps_cam_on_disconnect;
  dev_cbs.onError = ps_cam_on_error;
  camera_status_t st =
      ACameraManager_openCamera(ps_cam_mgr, id, &dev_cbs, &s->dev);
  if (st != ACAMERA_OK) {
    snprintf(ps_cam_err, sizeof(ps_cam_err), "openCamera(%s) = %d", id,
             (int)st);
    __android_log_print(ANDROID_LOG_INFO, "positron", "cam: open %s -> %d", id,
                        (int)st);
    free(s);
    return NULL;
  }
  if (AImageReader_new(w > 0 ? w : 1280, h > 0 ? h : 720,
                       AIMAGE_FORMAT_YUV_420_888, 3, &s->reader) !=
          AMEDIA_OK ||
      !s->reader ||
      AImageReader_getWindow(s->reader, &s->win) != AMEDIA_OK || !s->win) {
    snprintf(ps_cam_err, sizeof(ps_cam_err), "image reader failed");
    positron_cam_close(s);
    return NULL;
  }
  ANativeWindow_acquire(s->win);
  ACameraCaptureSession_stateCallbacks sess_cbs;
  memset(&sess_cbs, 0, sizeof(sess_cbs));
  /* Chained ||: each step runs until one fails (ACAMERA_OK == 0). */
  int rc = ACaptureSessionOutputContainer_create(&s->outputs) ||
           ACaptureSessionOutput_create(s->win, &s->soutput) ||
           ACaptureSessionOutputContainer_add(s->outputs, s->soutput) ||
           ACameraDevice_createCaptureSession(s->dev, s->outputs, &sess_cbs,
                                              &s->session) ||
           ACameraDevice_createCaptureRequest(s->dev, TEMPLATE_PREVIEW,
                                              &s->req) ||
           ACameraOutputTarget_create(s->win, &s->target) ||
           ACaptureRequest_addTarget(s->req, s->target);
  if (rc != 0) {
    snprintf(ps_cam_err, sizeof(ps_cam_err), "capture session setup = %d", rc);
    positron_cam_close(s);
    return NULL;
  }
  if (ACameraCaptureSession_setRepeatingRequest(s->session, NULL, 1, &s->req,
                                                NULL) != ACAMERA_OK) {
    snprintf(ps_cam_err, sizeof(ps_cam_err), "repeating request failed");
    positron_cam_close(s);
    return NULL;
  }
  __android_log_print(ANDROID_LOG_INFO, "positron",
                      "cam: session open id=%s rot=%d mirror=%d", id, s->rot,
                      s->mirror);
  return s;
}

static int ps_cam_clip(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }

/* 1 when a NEW frame arrived; *data then points at shim-owned RGBA
 * pixels (w*h*4) valid until the next call (the adapter's contract). */
int positron_cam_frame(void *sp, const uint8_t **out, int *w, int *h) {
  struct ps_cam *s = sp;
  AImage *img = NULL;
  if (!s || !s->reader) return 0;
  if (AImageReader_acquireLatestImage(s->reader, &img) != AMEDIA_OK || !img)
    return 0;
  int32_t cw = 0, ch = 0;
  AImage_getWidth(img, &cw);
  AImage_getHeight(img, &ch);
  /* Output dims after the sensor rotation (90/270 swap the sides). */
  const int ow = (s->rot == 90 || s->rot == 270) ? ch : cw;
  const int oh = (s->rot == 90 || s->rot == 270) ? cw : ch;
  int got = 0;
  if (cw > 0 && ch > 0) {
    if (ow != s->w || oh != s->h) {
      free(s->rgba);
      s->rgba = malloc((size_t)ow * oh * 4);
      s->w = ow;
      s->h = oh;
    }
    uint8_t *py = NULL, *pu = NULL, *pv = NULL;
    int32_t rs0 = 0, rs1 = 0, ps0 = 1, ps1 = 1;
    int ly = 0, lu = 0, lv = 0;
    /* Plane 2 shares plane 1's stride layout (guaranteed for the
     * interleaved semi-planar case, true of every planar device). */
    if (s->rgba &&
        AImage_getPlaneData(img, 0, &py, &ly) == AMEDIA_OK &&
        AImage_getPlaneData(img, 1, &pu, &lu) == AMEDIA_OK &&
        AImage_getPlaneData(img, 2, &pv, &lv) == AMEDIA_OK &&
        AImage_getPlaneRowStride(img, 0, &rs0) == AMEDIA_OK &&
        AImage_getPlaneRowStride(img, 1, &rs1) == AMEDIA_OK &&
        AImage_getPlanePixelStride(img, 0, &ps0) == AMEDIA_OK &&
        AImage_getPlanePixelStride(img, 1, &ps1) == AMEDIA_OK) {
      const int rot = s->rot;
      for (int y = 0; y < ch; y++) {
        const uint8_t *yr = py + (size_t)y * rs0;
        const uint8_t *ur = pu + (size_t)(y >> 1) * rs1;
        const uint8_t *vr = pv + (size_t)(y >> 1) * rs1;
        for (int x = 0; x < cw; x++) {
          int Y = (yr[x * ps0] - 16) * 298;
          int U = ur[(x >> 1) * ps1] - 128;
          int V = vr[(x >> 1) * ps1] - 128;
          /* Where this source pixel lands after the clockwise sensor
           * rotation. */
          int ox, oy;
          switch (rot) {
            case 90:  ox = ch - 1 - y; oy = x;          break;
            case 180: ox = cw - 1 - x; oy = ch - 1 - y; break;
            case 270: ox = y;          oy = cw - 1 - x; break;
            default:  ox = x;          oy = y;          break;
          }
          if (s->mirror) ox = ow - 1 - ox;
          uint8_t *o = s->rgba + ((size_t)oy * ow + ox) * 4;
          o[0] = (uint8_t)ps_cam_clip((Y + 409 * V + 128) >> 8);
          o[1] = (uint8_t)ps_cam_clip((Y - 100 * U - 208 * V + 128) >> 8);
          o[2] = (uint8_t)ps_cam_clip((Y + 516 * U + 128) >> 8);
          o[3] = 255;
        }
      }
      *out = s->rgba;
      *w = ow;
      *h = oh;
      got = 1;
    }
  }
  AImage_delete(img);
  return got;
}

void positron_cam_close(void *sp) {
  struct ps_cam *s = sp;
  if (!s) return;
  if (s->session) {
    ACameraCaptureSession_stopRepeating(s->session);
    ACameraCaptureSession_close(s->session);
  }
  if (s->req) ACaptureRequest_free(s->req);
  if (s->target) ACameraOutputTarget_free(s->target);
  if (s->soutput) ACaptureSessionOutput_free(s->soutput);
  if (s->outputs) ACaptureSessionOutputContainer_free(s->outputs);
  if (s->dev) ACameraDevice_close(s->dev);
  if (s->win) ANativeWindow_release(s->win);
  if (s->reader) AImageReader_delete(s->reader);
  free(s->rgba);
  free(s);
}

const char *positron_cam_last_error(void) { return ps_cam_err; }
