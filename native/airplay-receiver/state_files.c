#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include "state_files.h"

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

int sf_write(const char *dir, const char *name, const char *content) {
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
