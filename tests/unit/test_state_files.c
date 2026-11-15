#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <pthread.h>
#include "state_files.h"

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)

static char base[256];

static int slurp(const char *path, char *buf, size_t n) {
	FILE *f = fopen(path, "r");
	if (!f) return -1;
	size_t r = fread(buf, 1, n - 1, f);
	buf[r] = 0;
	fclose(f);
	return (int)r;
}

static void test_init_creates_nested_dir_and_clears_stale(void) {
	char dir[300], path[400], buf[64];
	snprintf(dir, sizeof(dir), "%s/a/b", base);
	CHECK(sf_init(dir) == 0);
	struct stat st;
	CHECK(stat(dir, &st) == 0 && S_ISDIR(st.st_mode));
	snprintf(path, sizeof(path), "%s/stream", dir);
	FILE *f = fopen(path, "w"); fputs("old", f); fclose(f);
	CHECK(sf_init(dir) == 0);
	CHECK(slurp(path, buf, sizeof(buf)) < 0);
}

static void test_write_is_exact_and_leaves_no_tmp(void) {
	char dir[300], path[400], buf[64];
	snprintf(dir, sizeof(dir), "%s/w", base);
	CHECK(sf_init(dir) == 0);
	CHECK(sf_write(dir, "volume", "0.500\n") == 0);
	snprintf(path, sizeof(path), "%s/volume", dir);
	CHECK(slurp(path, buf, sizeof(buf)) == 6 && strcmp(buf, "0.500\n") == 0);
	CHECK(sf_write(dir, "volume", "1.000\n") == 0);
	CHECK(slurp(path, buf, sizeof(buf)) == 6 && strcmp(buf, "1.000\n") == 0);
	snprintf(path, sizeof(path), "%s/volume.tmp", dir);
	CHECK(access(path, F_OK) != 0);
}

static void test_write_to_missing_dir_fails(void) {
	char dir[300];
	snprintf(dir, sizeof(dir), "%s/does/not/exist", base);
	CHECK(sf_write(dir, "state", "playing\n") == -1);
}

static char race_dir[300];
static int race_errors;

static void *race_writer(void *arg) {
	const char *content = arg;
	for (int i = 0; i < 2000; i++)
		if (sf_write(race_dir, "state", content)) __sync_fetch_and_add(&race_errors, 1);
	return NULL;
}

/* libraop calls back from the RTSP and streamer threads at the same time */
static void test_concurrent_writers_never_fail_or_mix(void) {
	char path[400], buf[64];
	snprintf(race_dir, sizeof(race_dir), "%s/race", base);
	CHECK(sf_init(race_dir) == 0);
	pthread_t a, b;
	pthread_create(&a, NULL, race_writer, "playing\n");
	pthread_create(&b, NULL, race_writer, "stopped\n");
	pthread_join(a, NULL);
	pthread_join(b, NULL);
	CHECK(race_errors == 0);
	snprintf(path, sizeof(path), "%s/state", race_dir);
	slurp(path, buf, sizeof(buf));
	CHECK(!strcmp(buf, "playing\n") || !strcmp(buf, "stopped\n"));
}

int main(void) {
	snprintf(base, sizeof(base), "/tmp/opencode/sf-test-%d", (int)getpid());
	test_init_creates_nested_dir_and_clears_stale();
	test_write_is_exact_and_leaves_no_tmp();
	test_write_to_missing_dir_fails();
	test_concurrent_writers_never_fail_or_mix();
	char cmd[300];
	snprintf(cmd, sizeof(cmd), "rm -rf %s", base);
	if (system(cmd)) {}
	if (failures) { printf("%d failure(s)\n", failures); return 1; }
	printf("state_files: all passed\n");
	return 0;
}
