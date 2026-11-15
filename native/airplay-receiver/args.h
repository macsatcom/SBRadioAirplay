#ifndef AR_ARGS_H
#define AR_ARGS_H

#include <netinet/in.h>

typedef struct {
	char name[64];                        /* --name, default "Squeezebox" */
	struct in_addr ip;                    /* --ip, 0 = pick first non-loopback IPv4 */
	char codec[8];                        /* --codec pcm|wav, default "pcm" */
	unsigned short port_base, port_range; /* --ports 6000:100 */
	int log_level;                        /* -d 0..5, default 2 */
} ar_args_t;

/* 0 ok, 1 --help requested, -1 usage error */
int ar_parse_args(int argc, char **argv, ar_args_t *out);
void ar_usage(const char *prog);

#endif
