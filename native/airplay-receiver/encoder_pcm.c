/*
 * PCM/WAV-only implementation of libcodecs' encoder.h, so raop_streamer can be
 * built without the FLAC/MP3/AAC libraries.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <strings.h>
#include "encoder.h"

#define WAV_HEADER_SIZE 44

struct encoder_s {
	bool wav;
	bool header_pending;
	char mimetype[64];
	size_t max_frames;
	uint8_t *data;
	size_t data_size;
};

static const uint8_t wav_header[WAV_HEADER_SIZE] = {
	'R', 'I', 'F', 'F', 0x24, 0xff, 0xff, 0xff, 'W', 'A', 'V', 'E',
	'f', 'm', 't', ' ', 16, 0, 0, 0, 1, 0, 2, 0,
	0x44, 0xac, 0x00, 0x00, 0x10, 0xb1, 0x02, 0x00, 4, 0, 16, 0,
	'd', 'a', 't', 'a', 0xff, 0xff, 0xff, 0xff,
};

struct encoder_s *encoder_create(char *codec, uint32_t sample_rate, uint8_t channels,
								 uint8_t sample_size, size_t max_frames, size_t *icy_interval) {
	bool wav;

	if (!strncasecmp(codec, "pcm", 3)) wav = false;
	else if (!strncasecmp(codec, "wav", 3)) wav = true;
	else return NULL;

	struct encoder_s *e = calloc(1, sizeof(*e));
	if (!e) return NULL;
	e->wav = wav;
	e->max_frames = 2 * max_frames > ENCODER_MAX_FRAMES ? 2 * max_frames : ENCODER_MAX_FRAMES;
	if (wav) strcpy(e->mimetype, "audio/wav");
	else snprintf(e->mimetype, sizeof(e->mimetype), "audio/L16;rate=%u;channels=2", sample_rate);
	/* same ICY interval upstream uses for uncompressed formats */
	if (icy_interval) *icy_interval = 128 * 1024;
	return e;
}

void encoder_delete(struct encoder_s *e) {
	if (!e) return;
	encoder_close(e);
	free(e);
}

bool encoder_open(struct encoder_s *e) {
	if (!e) return false;
	e->header_pending = e->wav;
	return true;
}

void encoder_close(struct encoder_s *e) {
	if (!e) return;
	free(e->data);
	e->data = NULL;
	e->data_size = 0;
}

uint8_t *encoder_encode(struct encoder_s *e, int16_t *pcm, size_t frames, size_t *bytes) {
	if (!e) return NULL;
	*bytes = frames * 4;

	if (!e->wav) {
		for (size_t i = 0; i < frames * 2; i++) pcm[i] = (int16_t)__builtin_bswap16((uint16_t)pcm[i]);
		return (uint8_t *)pcm;
	}

	if (!e->header_pending) return (uint8_t *)pcm;

	size_t need = WAV_HEADER_SIZE + *bytes;
	if (need > e->data_size) {
		uint8_t *p = realloc(e->data, need);
		if (!p) return NULL;
		e->data = p;
		e->data_size = need;
	}
	memcpy(e->data, wav_header, WAV_HEADER_SIZE);
	memcpy(e->data + WAV_HEADER_SIZE, pcm, *bytes);
	*bytes = need;
	e->header_pending = false;
	return e->data;
}

char *encoder_mimetype(struct encoder_s *e) {
	return e ? e->mimetype : NULL;
}

size_t encoder_space(struct encoder_s *e) {
	return e ? e->max_frames / 2 : 0;
}
