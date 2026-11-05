// System JavaScriptCore public C API only. No private watchdog symbols.
#include <JavaScriptCore/JavaScript.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
  _Atomic unsigned references;
  _Atomic int64_t cancelled_through;
  JSGlobalContextRef context;
  double deadline;
  int64_t request;
  int stopped; // 2 cancelled, 3 deadline
} PeleEngine;

static double monotonic_seconds(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec + now.tv_nsec / 1e9;
}

void *ianvs_pele_allocate(void) {
  PeleEngine *engine = calloc(1, sizeof(*engine));
  if (!engine) return NULL;
  atomic_init(&engine->references, 1);
  atomic_init(&engine->cancelled_through, -1);
  return engine;
}
void ianvs_pele_retain(void *pointer) {
  atomic_fetch_add(&((PeleEngine *)pointer)->references, 1);
}
void ianvs_pele_release(void *pointer) {
  if (pointer && atomic_fetch_sub(&((PeleEngine *)pointer)->references, 1) == 1)
    free(pointer);
}
void ianvs_pele_cancel(void *pointer, int64_t through) {
  PeleEngine *engine = pointer;
  int64_t previous = atomic_load(&engine->cancelled_through);
  while (previous < through && !atomic_compare_exchange_weak(
      &engine->cancelled_through, &previous, through)) {}
}
static int stopped(PeleEngine *engine) {
  if (engine->request <= atomic_load(&engine->cancelled_through)) return 2;
  if (monotonic_seconds() >= engine->deadline) return 3;
  return 0;
}
static JSValueRef check(JSContextRef context, JSObjectRef function,
                       JSObjectRef this_object, size_t count,
                       const JSValueRef arguments[], JSValueRef *exception) {
  (void)function; (void)this_object; (void)count; (void)arguments;
  PeleEngine *engine = JSObjectGetPrivate(JSContextGetGlobalObject(context));
  engine->stopped = stopped(engine);
  if (engine->stopped) {
    JSStringRef message = JSStringCreateWithUTF8CString(
        engine->stopped == 2 ? "Pele execution cancelled" : "Pele execution deadline exceeded");
    *exception = JSValueMakeString(context, message);
    JSStringRelease(message);
  }
  return JSValueMakeUndefined(context);
}
static char *string_copy(JSContextRef context, JSValueRef value) {
  if (!value) return strdup("JavaScript returned no value");
  JSStringRef string = JSValueToStringCopy(context, value, NULL);
  if (!string) return strdup("Cannot read JavaScript result");
  size_t size = JSStringGetMaximumUTF8CStringSize(string);
  char *result = malloc(size);
  if (result) JSStringGetUTF8CString(string, result, size);
  JSStringRelease(string);
  return result;
}
// Must be called only on the serial rendering worker, never concurrently.
void ianvs_pele_close(void *pointer) {
  PeleEngine *engine = pointer;
  if (engine->context) {
    JSGlobalContextRelease(engine->context);
    engine->context = NULL;
  }
}
char *ianvs_pele_evaluate(void *pointer, const char *script, int64_t request,
                         double seconds, int32_t *status) {
  PeleEngine *engine = pointer;
  engine->request = request;
  engine->deadline = monotonic_seconds() + seconds;
  engine->stopped = stopped(engine);
  *status = engine->stopped;
  if (*status) return strdup("Pele execution cancelled before start");
  if (!engine->context) {
    JSClassDefinition definition = kJSClassDefinitionEmpty;
    JSClassRef klass = JSClassCreate(&definition);
    engine->context = JSGlobalContextCreate(klass);
    JSClassRelease(klass);
    JSObjectRef global = JSContextGetGlobalObject(engine->context);
    JSObjectSetPrivate(global, engine);
    JSStringRef name = JSStringCreateWithUTF8CString("__linefoldNativeCheck");
    JSObjectRef callback = JSObjectMakeFunctionWithCallback(engine->context, name, check);
    JSObjectSetProperty(engine->context, global, name, callback,
                       kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete, NULL);
    JSStringRelease(name);
  }
  JSStringRef source = JSStringCreateWithUTF8CString(script);
  JSValueRef exception = NULL;
  JSValueRef value = JSEvaluateScript(engine->context, source, NULL, NULL, 1, &exception);
  JSStringRelease(source);
  char *result = string_copy(engine->context, exception ? exception : value);
  // A builtin can return after its budget without visiting a checkpoint.
  // Detect this late overrun, but do not claim it was preempted.
  if (!engine->stopped) engine->stopped = stopped(engine);
  *status = engine->stopped ? engine->stopped : exception ? 1 : 0;
  if (engine->stopped && !exception) {
    free(result);
    result = strdup(engine->stopped == 2 ? "Pele execution cancelled" :
                    "Pele execution deadline exceeded (checked after evaluation)");
  }
  JSGarbageCollect(engine->context);
  if (*status == 2 || *status == 3) ianvs_pele_close(engine);
  return result;
}
void ianvs_pele_free(char *pointer) { free(pointer); }
