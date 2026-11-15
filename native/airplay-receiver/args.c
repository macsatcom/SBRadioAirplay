#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include "args.h"

void ar_usage(const char *prog) {
	fprintf(stderr,
		"usage: %s [--name <speaker name>] [--ip <ipv4>] [--codec pcm|wav]\n"
		"          [--ports <base>:<range>] [-d <0..5>] [--help]\n", prog);
}

static int parse_ports(const char *s, unsigned short *base, unsigned short *range) {
	char *end;
	unsigned long b = strtoul(s, &end, 10);
	if (end == s || *end != ':') return -1;
	const char *r = end + 1;
	unsigned long n = strtoul(r, &end, 10);
	if (end == r || *end || b == 0 || n == 0 || b + n > 65536) return -1;
	*base = (unsigned short)b;
	*range = (unsigned short)n;
	return 0;
}

int ar_parse_args(int argc, char **argv, ar_args_t *out) {
	memset(out, 0, sizeof(*out));
	strcpy(out->name, "Squeezebox");
	strcpy(out->codec, "pcm");
	out->port_base = 6000;
	out->port_range = 100;
	out->log_level = 2;

	for (int i = 1; i < argc; i++) {
		const char *opt = argv[i];
		if (!strcmp(opt, "--help") || !strcmp(opt, "-h")) return 1;
		if (i + 1 >= argc) return -1;
		const char *val = argv[++i];

		if (!strcmp(opt, "--name")) {
			if (!*val || strlen(val) >= sizeof(out->name)) return -1;
			strcpy(out->name, val);
		} else if (!strcmp(opt, "--codec")) {
			if (strcmp(val, "pcm") && strcmp(val, "wav")) return -1;
			strcpy(out->codec, val);
		} else if (!strcmp(opt, "--ports")) {
			if (parse_ports(val, &out->port_base, &out->port_range)) return -1;
		} else if (!strcmp(opt, "--ip")) {
			if (inet_pton(AF_INET, val, &out->ip) != 1) return -1;
		} else if (!strcmp(opt, "-d")) {
			char *end;
			long l = strtol(val, &end, 10);
			if (end == val || *end || l < 0 || l > 5) return -1;
			out->log_level = (int)l;
		} else {
			return -1;
		}
	}
	return 0;
}
