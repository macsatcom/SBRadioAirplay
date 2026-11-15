/*
 * airplay-receiver: AirPlay 1 (RAOP) receiver for Squeezebox Radio/Touch.
 * Announces itself over mDNS and serves decoded audio over HTTP.
 * Prints one event line per receiver event on stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdbool.h>
#include <signal.h>
#include <pthread.h>
#include <arpa/inet.h>

#include "platform.h"
#include "cross_log.h"
#include "cross_net.h"
#include "mdnssvc.h"
#include "raop_server.h"
#include "raop_streamer.h"
#include "state_files.h"
#include "args.h"

log_level raop_loglevel = lWARN;
log_level util_loglevel = lWARN;

static struct in_addr host;
static const char *state_dir;
static unsigned stream_generation;
static bool session_live;
/* raop_cb runs on the RTSP thread and (for PLAY) on the streamer thread */
static pthread_mutex_t cb_lock = PTHREAD_MUTEX_INITIALIZER;

static void state(const char *name, const char *fmt, ...) {
	char buf[1024];
	va_list ap;
	if (!state_dir) return;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	if (sf_write(state_dir, name, buf)) fprintf(stderr, "cannot write state file %s\n", name);
}

static void event(const char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	putchar('\n');
	fflush(stdout);
}

static const char *nz(const char *s) { return s ? s : ""; }

/* metadata file is line-based: keep each field on one line */
static const char *oneline(const char *s) {
	static char bufs[3][256];
	static int n;
	char *b = bufs[n++ % 3];
	snprintf(b, sizeof(bufs[0]), "%s", nz(s));
	for (char *p = b; *p; p++) if (*p == '\n' || *p == '\r') *p = ' ';
	return b;
}

static void raop_cb(void *owner, raopsr_event_t ev, ...) {
	va_list ap;
	(void)owner;
	pthread_mutex_lock(&cb_lock);
	va_start(ap, ev);
	switch (ev) {
	case RAOP_STREAM: {
		unsigned port = va_arg(ap, uint32_t);
		event("STREAM port=%u url=http://%s:%u/stream", port,
			  raopst_http_loopback ? "127.0.0.1" : inet_ntoa(host), port);
		state("stream", "%u %u\n", ++stream_generation, port);
		state("state", "playing\n");
		session_live = true;
		break;
	}
	case RAOP_PLAY:
		event("PLAY");
		/* the streamer thread can report PLAY after the session was stopped */
		if (session_live) state("state", "playing\n");
		break;
	case RAOP_PAUSE: event("PAUSE"); state("state", "flushed\n"); break;
	case RAOP_FLUSH: event("FLUSH"); state("state", "flushed\n"); break;
	case RAOP_STOP:  event("STOP"); state("state", "stopped\n"); session_live = false; break;
	case RAOP_VOLUME: {
		double v = va_arg(ap, double);
		event("VOLUME %.3f", v);
		state("volume", "%.3f\n", v < 0 ? 0.0 : v > 1 ? 1.0 : v);
		break;
	}
	case RAOP_METADATA: {
		raopsr_metadata_t *m = va_arg(ap, raopsr_metadata_t *);
		event("METADATA title=%s\tartist=%s\talbum=%s", nz(m->title), nz(m->artist), nz(m->album));
		state("metadata", "%s\n%s\n%s\n", oneline(m->title), oneline(m->artist), oneline(m->album));
		break;
	}
	case RAOP_ARTWORK: {
		(void)va_arg(ap, raopsr_metadata_t *);
		(void)va_arg(ap, char *);
		event("ARTWORK %d", va_arg(ap, int));
		break;
	}
	}
	va_end(ap);
	pthread_mutex_unlock(&cb_lock);
}

int main(int argc, char **argv) {
	ar_args_t args;
	int rc = ar_parse_args(argc, argv, &args);
	if (rc) {
		ar_usage(argv[0]);
		return rc > 0 ? 0 : 2;
	}

	raop_loglevel = util_loglevel = (log_level)args.log_level;
	raopst_http_loopback = !args.http_lan;
	if (args.state_dir[0]) {
		if (sf_init(args.state_dir)) {
			fprintf(stderr, "cannot create state dir %s\n", args.state_dir);
			return 1;
		}
		state_dir = args.state_dir;
		state("state", "stopped\n");
	}

	/* Block before creating threads so only sigwait sees them. */
	sigset_t set;
	sigemptyset(&set);
	sigaddset(&set, SIGINT);
	sigaddset(&set, SIGTERM);
	pthread_sigmask(SIG_BLOCK, &set, NULL);
	signal(SIGPIPE, SIG_IGN);

	netsock_init();
	host = args.ip;
	if (!host.s_addr) host = get_interface(NULL, NULL, NULL);
	if (!host.s_addr || host.s_addr == INADDR_NONE) {
		fprintf(stderr, "no usable IPv4 interface, use --ip\n");
		return 1;
	}

	unsigned char mac[6] = { 0 };
	get_mac(mac);
	if (!(mac[0] | mac[1] | mac[2] | mac[3] | mac[4] | mac[5])) {
		uint32_t a = ntohl(host.s_addr);
		mac[0] = 0x02; mac[1] = 0x5b;
		mac[2] = a >> 24; mac[3] = a >> 16; mac[4] = a >> 8; mac[5] = a;
	}

	struct mdnsd *svr = mdnsd_start(host, args.log_level >= lDEBUG);
	if (!svr) {
		fprintf(stderr, "cannot start mDNS responder\n");
		return 1;
	}
	char hostname[80];
	snprintf(hostname, sizeof(hostname), "airplay-%02x%02x%02x", mac[3], mac[4], mac[5]);
	mdnsd_set_hostname(svr, hostname, host);

	struct raopsr_s *raop = raopsr_create(host, svr, args.name, "SqueezeboxRadio", mac,
										  args.codec, true, true, false, "1000:0", NULL,
										  raop_cb, NULL, args.port_base, args.port_range, 0);
	if (!raop) {
		fprintf(stderr, "cannot start RAOP receiver\n");
		mdnsd_stop(svr);
		return 1;
	}

	event("READY name=%s ip=%s", args.name, inet_ntoa(host));

	int sig;
	sigwait(&set, &sig);

	raopsr_delete(raop);
	mdnsd_stop(svr);
	netsock_close();
	return 0;
}
