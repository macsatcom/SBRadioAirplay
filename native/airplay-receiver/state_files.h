#ifndef AR_STATE_FILES_H
#define AR_STATE_FILES_H

/* Small state files read by the Jive applet. Each write is atomic
 * (<name>.tmp + rename) so a reader never sees a partial file. */

int sf_init(const char *dir);                                      /* mkdir -p, drop stale files; 0 ok */
int sf_write(const char *dir, const char *name, const char *content); /* 0 ok, -1 error */

#endif
