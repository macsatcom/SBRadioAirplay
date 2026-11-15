#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "encoder.h"

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)

static void fill(int16_t *pcm, size_t frames) {
	for (size_t i = 0; i < frames * 2; i++) pcm[i] = (int16_t)(0x0102 + i);
}

static void test_pcm_is_big_endian_l16(void) {
	size_t icy = 0, bytes = 0;
	int16_t pcm[352 * 2];
	struct encoder_s *e = encoder_create("pcm", 44100, 2, 2, 0, &icy);
	CHECK(e != NULL);
	if (!e) return;
	CHECK(strcmp(encoder_mimetype(e), "audio/L16;rate=44100;channels=2") == 0);
	CHECK(encoder_open(e));
	fill(pcm, 352);
	uint8_t *out = encoder_encode(e, pcm, 352, &bytes);
	CHECK(bytes == 1408);
	CHECK(out[0] == 0x01 && out[1] == 0x02);
	CHECK(out[2] == 0x01 && out[3] == 0x03);
	encoder_delete(e);
}

static void check_wav_header(const uint8_t *h) {
	CHECK(memcmp(h, "RIFF", 4) == 0);
	CHECK(memcmp(h + 8, "WAVE", 4) == 0);
	CHECK(memcmp(h + 12, "fmt ", 4) == 0);
	CHECK(h[20] == 1 && h[21] == 0);                    /* PCM */
	CHECK(h[22] == 2 && h[23] == 0);                    /* channels */
	CHECK(h[24] == 0x44 && h[25] == 0xac && h[26] == 0 && h[27] == 0); /* 44100 */
	CHECK(h[34] == 16 && h[35] == 0);                   /* bits */
	CHECK(memcmp(h + 36, "data", 4) == 0);
	CHECK(h[40] == 0xff && h[41] == 0xff && h[42] == 0xff && h[43] == 0xff);
}

static void test_wav_header_then_little_endian(void) {
	size_t icy = 0, bytes = 0;
	int16_t pcm[352 * 2];
	struct encoder_s *e = encoder_create("wav", 44100, 2, 2, 0, &icy);
	CHECK(e != NULL);
	if (!e) return;
	CHECK(strcmp(encoder_mimetype(e), "audio/wav") == 0);
	CHECK(encoder_open(e));
	fill(pcm, 352);
	uint8_t *out = encoder_encode(e, pcm, 352, &bytes);
	CHECK(bytes == 44 + 1408);
	check_wav_header(out);
	CHECK(out[44] == 0x02 && out[45] == 0x01);
	fill(pcm, 352);
	out = encoder_encode(e, pcm, 352, &bytes);
	CHECK(bytes == 1408);
	CHECK(out[0] == 0x02 && out[1] == 0x01);
	encoder_close(e);
	CHECK(encoder_open(e));
	fill(pcm, 352);
	out = encoder_encode(e, pcm, 352, &bytes);
	CHECK(bytes == 44 + 1408);
	check_wav_header(out);
	encoder_delete(e);
}

static void test_other_codecs_rejected(void) {
	size_t icy = 0;
	CHECK(encoder_create("mp3", 44100, 2, 2, 0, &icy) == NULL);
	CHECK(encoder_create("flc", 44100, 2, 2, 0, &icy) == NULL);
}

int main(void) {
	test_pcm_is_big_endian_l16();
	test_wav_header_then_little_endian();
	test_other_codecs_rejected();
	if (failures) { printf("%d failure(s)\n", failures); return 1; }
	printf("encoder: all passed\n");
	return 0;
}
