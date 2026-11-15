#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include <pthread.h>
#include "state_files.h"

static int sf_write_locked(const char *dir, const char *name, const char *content);

static const char *const names[] = { "stream", "state", "volume", "metadata", NULL };

static int mkdir_p(const char *dir) {
	char buf[256];
	if (strlen(dir) >= sizeof(buf)) return -1;
	strcpy(buf, dir);
	for (char *p = buf + 1; *p; p++) {
		if (*p != '/') continue;
		*p = 0;
		if (mkdir(buf, 0755) && errno != EEXIST) return -1;
		*p = '/';
	}
	if (mkdir(buf, 0755) && errno != EEXIST) return -1;
	return 0;
}

int sf_init(const char *dir) {
	char path[300];
	if (mkdir_p(dir)) return -1;
	for (int i = 0; names[i]; i++) {
		snprintf(path, sizeof(path), "%s/%s", dir, names[i]);
		unlink(path);
	}
	return 0;
}

/* libraop calls back from several threads; they share <name>.tmp */
static pthread_mutex_t write_lock = PTHREAD_MUTEX_INITIALIZER;

int sf_write(const char *dir, const char *name, const char *content) {
	pthread_mutex_lock(&write_lock);
	int rc = sf_write_locked(dir, name, content);
	pthread_mutex_unlock(&write_lock);
	return rc;
}

static int sf_write_locked(const char *dir, const char *name, const char *content) {
	char path[300], tmp[310];
	snprintf(path, sizeof(path), "%s/%s", dir, name);
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	FILE *f = fopen(tmp, "w");
	if (!f) return -1;
	size_t len = strlen(content);
	int ok = fwrite(content, 1, len, f) == len;
	ok &= fclose(f) == 0;
	if (!ok || rename(tmp, path)) {
		unlink(tmp);
		return -1;
	}
	return 0;
}
