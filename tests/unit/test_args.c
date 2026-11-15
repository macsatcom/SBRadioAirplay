#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>
#include "args.h"

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)
#define ARGC(a) ((int)(sizeof(a) / sizeof((a)[0])))

static void test_defaults(void) {
	char *argv[] = { "airplay-receiver" };
	ar_args_t a;
	CHECK(ar_parse_args(ARGC(argv), argv, &a) == 0);
	CHECK(strcmp(a.name, "Squeezebox") == 0);
	CHECK(strcmp(a.codec, "pcm") == 0);
	CHECK(a.port_base == 6000 && a.port_range == 100);
	CHECK(a.log_level == 2);
	CHECK(a.ip.s_addr == 0); /* resolved later by main */
	CHECK(a.state_dir[0] == 0);
	CHECK(!a.http_lan);
}

static void test_all_options(void) {
	char *argv[] = { "x", "--name", "Kitchen Radio", "--codec", "wav", "--ports", "7000:10",
					 "-d", "4", "--ip", "192.168.1.5" };
	ar_args_t a;
	CHECK(ar_parse_args(ARGC(argv), argv, &a) == 0);
	CHECK(strcmp(a.name, "Kitchen Radio") == 0);
	CHECK(strcmp(a.codec, "wav") == 0);
	CHECK(a.port_base == 7000 && a.port_range == 10);
	CHECK(a.log_level == 4);
	CHECK(a.ip.s_addr == inet_addr("192.168.1.5"));
}

static void test_state_dir_and_http_lan(void) {
	char *argv[] = { "x", "--state-dir", "/tmp/airplay", "--http-lan" };
	ar_args_t a;
	CHECK(ar_parse_args(ARGC(argv), argv, &a) == 0);
	CHECK(strcmp(a.state_dir, "/tmp/airplay") == 0);
	CHECK(a.http_lan);
	char *missing[] = { "x", "--state-dir" };
	CHECK(ar_parse_args(ARGC(missing), missing, &a) == -1);
}

static void test_rejects(void) {
	ar_args_t a;
	char *bad_codec[] = { "x", "--codec", "mp3" };
	char *bad_ports[] = { "x", "--ports", "7000" };
	char *bad_ip[] = { "x", "--ip", "nope" };
	char *missing[] = { "x", "--name" };
	char *unknown[] = { "x", "--bogus" };
	char *long_name[] = { "x", "--name",
		"0123456789012345678901234567890123456789012345678901234567890123456789" };
	CHECK(ar_parse_args(ARGC(bad_codec), bad_codec, &a) == -1);
	CHECK(ar_parse_args(ARGC(bad_ports), bad_ports, &a) == -1);
	CHECK(ar_parse_args(ARGC(bad_ip), bad_ip, &a) == -1);
	CHECK(ar_parse_args(ARGC(missing), missing, &a) == -1);
	CHECK(ar_parse_args(ARGC(unknown), unknown, &a) == -1);
	CHECK(ar_parse_args(ARGC(long_name), long_name, &a) == -1);
}

static void test_help(void) {
	char *argv[] = { "x", "--help" };
	ar_args_t a;
	CHECK(ar_parse_args(ARGC(argv), argv, &a) == 1);
}

int main(void) {
	test_defaults();
	test_all_options();
	test_state_dir_and_http_lan();
	test_rejects();
	test_help();
	if (failures) { printf("%d failure(s)\n", failures); return 1; }
	printf("args: all passed\n");
	return 0;
}
