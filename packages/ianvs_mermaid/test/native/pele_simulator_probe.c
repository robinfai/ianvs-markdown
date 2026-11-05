// Standalone Apple probe of the same production bridge (no private APIs).
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
extern void *ianvs_pele_allocate(void);
extern void ianvs_pele_cancel(void *, int64_t);
extern void ianvs_pele_close(void *);
extern void ianvs_pele_release(void *);
extern char *ianvs_pele_evaluate(void *, const char *, int64_t, double, int32_t *);
extern void ianvs_pele_free(char *);
static void *cancel(void *engine) {
  usleep(80000);
  ianvs_pele_cancel(engine, 2);
  return NULL;
}
static char *read_file(const char *path) {
  FILE *file = fopen(path, "rb"); assert(file);
  fseek(file, 0, SEEK_END); long size = ftell(file); assert(size > 0);
  rewind(file); char *text = calloc((size_t)size + 1, 1); assert(text);
  assert(fread(text, 1, (size_t)size, file) == (size_t)size);
  fclose(file); return text;
}
static double now(void) {
  struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec / 1e9;
}
int main(int argc, char **argv) {
  assert(argc == 3);
  void *engine = ianvs_pele_allocate(); assert(engine);
  char *loop = read_file(argv[1]); char *runtime = read_file(argv[2]);
  int32_t status = 0;
  double start = now();
  char *result = ianvs_pele_evaluate(engine, loop, 1, .08, &status);
  printf("timeout status=%d elapsed_ms=%.3f\n", status, (now()-start)*1000);
  assert(status == 3); ianvs_pele_free(result);
  pthread_t thread; assert(pthread_create(&thread, NULL, cancel, engine) == 0);
  start = now(); result = ianvs_pele_evaluate(engine, loop, 2, 5, &status);
  printf("cancel status=%d elapsed_ms=%.3f\n", status, (now()-start)*1000);
  pthread_join(thread, NULL); assert(status == 2); ianvs_pele_free(result);
  result = ianvs_pele_evaluate(engine, runtime, 3, 5, &status);
  assert(status == 0); ianvs_pele_free(result);
  result = ianvs_pele_evaluate(engine,
      "JSON.stringify(Pele.render('flowchart LR\\n中文节点-->结束',{responsive:false}))",
      4, 5, &status);
  assert(status == 0 && strstr(result, "<svg")); ianvs_pele_free(result);
  puts("recovery + Chinese-node rendering passed");
  ianvs_pele_close(engine); ianvs_pele_release(engine);
  free(loop); free(runtime); return 0;
}
