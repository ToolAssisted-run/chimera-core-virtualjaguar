/* cinterface.c - Virtual Jaguar's Atari Jaguar as a Chimera core: the
 * functions Chimera calls.
 *
 * Virtual Jaguar is a libretro core: a program around it calls its retro_*
 * functions and answers its questions through callbacks. This file is that
 * program, inside the sandbox. It answers the questions from the project
 * (its settings and its files), hands the picture and the sound out, and
 * puts the controls Chimera sets for each frame into the Jaguar's own
 * button tables (patch 0002).
 *
 * SPDX-License-Identifier: MIT
 */
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/time.h>
#include <time.h>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "libretro.h"
#include "joystick.h"

/* ---- what went wrong, for Chimera to show -------------------------------- */
static char g_loadError[512];

/* ---- the emulator's options ------------------------------------------------
 * Virtual Jaguar declares its options (key, values, default) when it is
 * given its environment. A project's setting with the option's name less
 * "virtualjaguar_" sets it; any other option keeps the default, which is the
 * first value when the option names none (libretro's rule). */
#define MAX_OPTIONS 256
static struct { const char *key; char value[128]; } g_options[MAX_OPTIONS];
static int g_optionCount;

static void take_option(const char *key, const char *def)
{
	if (!key || g_optionCount >= MAX_OPTIONS) return;
	for (int i = 0; i < g_optionCount; i++)
		if (!strcmp(g_options[i].key, key)) return;
	g_options[g_optionCount].key = key;
	const char *name = !strncmp(key, "virtualjaguar_", 14) ? key + 14 : key;
	if (wbx_setting_str(name, g_options[g_optionCount].value, sizeof g_options[g_optionCount].value) <= 0)
		snprintf(g_options[g_optionCount].value, sizeof g_options[g_optionCount].value, "%s", def ? def : "");
	g_optionCount++;
}

static const char *option_value(const char *key)
{
	for (int i = 0; i < g_optionCount; i++)
		if (!strcmp(g_options[i].key, key)) return g_options[i].value;
	return NULL;
}

/* ---- the picture -------------------------------------------------------- */
#define MAX_W 1440
#define MAX_H 1152
ECL_INVISIBLE static uint32_t g_picture[MAX_W * MAX_H];
static int g_width = 320, g_height = 240;
static int g_render = 1;

/* ---- the sound ---------------------------------------------------------- */
#define MAX_SAMPLES 8192
ECL_INVISIBLE static int16_t g_audio[MAX_SAMPLES * 2];
static int g_audioFrames;

/* ---- the controls -------------------------------------------------------
 * Two Jaguar controllers, each with its pad, A, B, C, Option, Pause and the
 * twelve keys of its keypad. They go into the Jaguar's own button tables
 * (joystick.c) at the end of the libretro layer's input step (patch 0002),
 * so its RetroPad mapping is given nothing. */
static const struct { const char *name; int button; } kPad[] = {
	{ "Up", BUTTON_U }, { "Down", BUTTON_D }, { "Left", BUTTON_L }, { "Right", BUTTON_R },
	{ "A", BUTTON_A }, { "B", BUTTON_B }, { "C", BUTTON_C }, { "Option", BUTTON_OPTION }, { "Pause", BUTTON_PAUSE },
	{ "1", BUTTON_1 }, { "2", BUTTON_2 }, { "3", BUTTON_3 }, { "4", BUTTON_4 }, { "5", BUTTON_5 }, { "6", BUTTON_6 },
	{ "7", BUTTON_7 }, { "8", BUTTON_8 }, { "9", BUTTON_9 }, { "*", BUTTON_s }, { "0", BUTTON_0 }, { "#", BUTTON_d },
};
#define PAD_BUTTONS ((int)(sizeof kPad / sizeof kPad[0]))
#define BUTTON_COUNT (2 * PAD_BUTTONS)
static char g_buttonNames[BUTTON_COUNT][16];
static int g_held[BUTTON_COUNT];
static int g_inputRead;
extern int chimera_input_reads;   /* joystick.c (patch 0003) */

void chimera_fill_joypads(void)
{
	for (int i = 0; i < PAD_BUTTONS; i++)
	{
		if (g_held[i]) joypad0Buttons[kPad[i].button] = 0xff;
		if (g_held[PAD_BUTTONS + i]) joypad1Buttons[kPad[i].button] = 0xff;
	}
}

/* ---- the clock ----------------------------------------------------------
 * The time any part of the core reads is the time the machine has run,
 * counted in frames, from the first of January 2000: the same in every run
 * and in every build. These definitions take the place of the C
 * library's; localtime() is UTC, as the sandbox's C library has it. */
static const int64_t kStartTime = 946684800;
static uint64_t g_frameCount;
static double g_fps = 60.0;

static int64_t emulated_usec(void)
{
	return (int64_t)((double)g_frameCount * 1000000.0 / g_fps);
}
time_t time(time_t *t)
{
	time_t v = (time_t)(kStartTime + emulated_usec() / 1000000);
	if (t) *t = v;
	return v;
}
int gettimeofday(struct timeval *restrict tv, void *restrict tz)
{
	(void)tz;
	int64_t us = emulated_usec();
	if (tv)
	{
		tv->tv_sec = (time_t)(kStartTime + us / 1000000);
		tv->tv_usec = (suseconds_t)(us % 1000000);
	}
	return 0;
}
int clock_gettime(clockid_t id, struct timespec *ts)
{
	(void)id;
	int64_t us = emulated_usec();
	ts->tv_sec = (time_t)(kStartTime + us / 1000000);
	ts->tv_nsec = (long)(us % 1000000) * 1000;
	return 0;
}
struct tm *localtime(const time_t *t) { return gmtime(t); }
struct tm *localtime_r(const time_t *restrict t, struct tm *restrict out) { return gmtime_r(t, out); }

/* ---- the callbacks Virtual Jaguar calls ---------------------------------- */
static void log_printf(enum retro_log_level level, const char *fmt, ...)
{
	static int all = -1;
	if (all < 0) all = getenv("CHIMERA_VJ_LOG") != NULL;
	if (level < RETRO_LOG_WARN && !all) return;
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
}

static bool environment(unsigned cmd, void *data)
{
	switch (cmd)
	{
	case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
		((struct retro_log_callback *)data)->log = log_printf;
		return true;
	case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
		*(unsigned *)data = 2;
		return true;
	case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
	{
		const struct retro_core_options_v2 *o = data;
		for (const struct retro_core_option_v2_definition *d = o ? o->definitions : NULL; d && d->key; d++)
			take_option(d->key, d->default_value ? d->default_value : d->values[0].value);
		return true;
	}
	case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
	{
		const struct retro_core_options_v2_intl *o = data;
		for (const struct retro_core_option_v2_definition *d = o && o->us ? o->us->definitions : NULL; d && d->key; d++)
			take_option(d->key, d->default_value ? d->default_value : d->values[0].value);
		return true;
	}
	case RETRO_ENVIRONMENT_GET_VARIABLE:
	{
		struct retro_variable *v = data;
		v->value = option_value(v->key);
		return v->value != NULL;
	}
	case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
		*(bool *)data = false;
		return true;
	/* The sandbox's files have no folders, and the core is given no
	 * folder: the boot ROMs it needs are built in. */
	case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
		return *(const enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_XRGB8888;
	case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
		g_fps = ((const struct retro_system_av_info *)data)->timing.fps;
		return true;
	case RETRO_ENVIRONMENT_SET_GEOMETRY:
		return true;
	default:
		return false;
	}
}

static void video_refresh(const void *data, unsigned width, unsigned height, size_t pitch)
{
	if (!data || !g_render) return;
	if (width > MAX_W) width = MAX_W;
	if (height > MAX_H) height = MAX_H;
	g_width = (int)width;
	g_height = (int)height;
	for (unsigned y = 0; y < height; y++)
	{
		const uint32_t *src = (const uint32_t *)((const uint8_t *)data + y * pitch);
		uint32_t *dst = g_picture + (size_t)y * width;
		for (unsigned x = 0; x < width; x++)
			dst[x] = src[x] | 0xFF000000u;
	}
}

static void audio_sample(int16_t left, int16_t right)
{
	if (g_audioFrames >= MAX_SAMPLES) return;
	g_audio[g_audioFrames * 2] = left;
	g_audio[g_audioFrames * 2 + 1] = right;
	g_audioFrames++;
}

static size_t audio_batch(const int16_t *data, size_t frames)
{
	size_t n = frames;
	if (n > (size_t)(MAX_SAMPLES - g_audioFrames)) n = (size_t)(MAX_SAMPLES - g_audioFrames);
	memcpy(g_audio + g_audioFrames * 2, data, n * 4);
	g_audioFrames += (int)n;
	return frames;
}

static void input_poll(void) {}

/* The libretro layer's own RetroPad mapping is given nothing: the controls
 * reach the Jaguar's tables directly (chimera_fill_joypads). */
static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
	(void)port; (void)device; (void)index; (void)id;
	return 0;
}

/* ---- the memory --------------------------------------------------------- */
struct memory_area { const char *name; uint8_t *bytes; int64_t size; };
static struct memory_area g_memory[4];
static int g_memoryCount;

/* ---- the files ---------------------------------------------------------- */
static char g_game[512];

/* the save file a project starts from: the first .eeprom/.srm/.sav in the
 * Save data slot */
static int read_save(uint8_t *into, size_t size)
{
	char name[512];
	int n = wbx_slot_count("savedata");
	for (int i = 0; i < n; i++)
	{
		if (!wbx_slot_name("savedata", i, name, sizeof name)) continue;
		FILE *f = fopen(name, "rb");
		if (!f) continue;
		size_t got = fread(into, 1, size, f);
		fclose(f);
		return got > 0;
	}
	return 0;
}

/* ---- Chimera's calls ---------------------------------------------------- */
ECL_EXPORT const char *GetLoadError(void) { return g_loadError; }
ECL_EXPORT const char *SuggestSettings(void) { return "{\"values\":{},\"note\":\"\",\"firmware\":[]}"; }
ECL_EXPORT const char *DescribeDips(void) { return ""; }

ECL_EXPORT int Init(void)
{
	g_loadError[0] = '\0';
	if (wbx_slot_count("cart") > 0)
		wbx_slot_name("cart", 0, g_game, sizeof g_game);
	if (!g_game[0])
	{
		/* a game opened with no project is mounted under its own name */
		FILE *f = fopen("rom.name", "rb");
		if (f)
		{
			size_t got = fread(g_game, 1, sizeof g_game - 1, f);
			g_game[got] = '\0';
			fclose(f);
		}
	}
	if (!g_game[0])
	{
		snprintf(g_loadError, sizeof g_loadError, "no game was given");
		return 0;
	}
	for (int p = 0; p < 2; p++)
		for (int i = 0; i < PAD_BUTTONS; i++)
			snprintf(g_buttonNames[p * PAD_BUTTONS + i], sizeof g_buttonNames[0], "P%d %s", p + 1, kPad[i].name);
	g_frameCount = 0;

	retro_set_environment(environment);
	retro_set_video_refresh(video_refresh);
	retro_set_audio_sample(audio_sample);
	retro_set_audio_sample_batch(audio_batch);
	retro_set_input_poll(input_poll);
	retro_set_input_state(input_state);
	retro_init();

	/* the game is read here and handed over whole */
	FILE *f = fopen(g_game, "rb");
	if (!f)
	{
		snprintf(g_loadError, sizeof g_loadError, "the game's file could not be read: %s", g_game);
		return 0;
	}
	fseek(f, 0, SEEK_END);
	long size = ftell(f);
	fseek(f, 0, SEEK_SET);
	void *bytes = size > 0 ? malloc((size_t)size) : NULL;
	if (!bytes || fread(bytes, 1, (size_t)size, f) != (size_t)size)
	{
		fclose(f);
		snprintf(g_loadError, sizeof g_loadError, "the game's file could not be read: %s", g_game);
		return 0;
	}
	fclose(f);
	struct retro_game_info info = { g_game, bytes, (size_t)size, NULL };
	if (!retro_load_game(&info))
	{
		snprintf(g_loadError, sizeof g_loadError, "the emulator did not start with %s", g_game);
		return 0;
	}
	struct retro_system_av_info av;
	retro_get_system_av_info(&av);
	g_fps = av.timing.fps;

	/* the cartridge's save memory, from the project's save file */
	uint8_t *save = retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
	size_t saveSize = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
	if (save && saveSize) read_save(save, saveSize);

	g_memoryCount = 0;
	uint8_t *ram = retro_get_memory_data(RETRO_MEMORY_SYSTEM_RAM);
	size_t ramSize = retro_get_memory_size(RETRO_MEMORY_SYSTEM_RAM);
	if (ram && ramSize) g_memory[g_memoryCount++] = (struct memory_area){ "Main RAM", ram, (int64_t)ramSize };
	if (save && saveSize) g_memory[g_memoryCount++] = (struct memory_area){ "Save RAM", save, (int64_t)saveSize };
	return 1;
}

ECL_EXPORT int GetButtonCount(void) { return BUTTON_COUNT; }
ECL_EXPORT const char *GetButtonName(int32_t i) { return i >= 0 && i < BUTTON_COUNT ? g_buttonNames[i] : ""; }
ECL_EXPORT int IsButtonActive(int32_t i) { return i >= 0 && i < BUTTON_COUNT; }
ECL_EXPORT void SetButton(int32_t i, int32_t state)
{
	if (i >= 0 && i < BUTTON_COUNT) g_held[i] = state != 0;
}

ECL_EXPORT int GetAxisCount(void) { return 0; }
ECL_EXPORT const char *GetAxisName(int32_t i) { (void)i; return ""; }
ECL_EXPORT int IsAxisActive(int32_t i) { (void)i; return 0; }
ECL_EXPORT void SetAxis(int32_t i, int32_t value) { (void)i; (void)value; }

ECL_EXPORT void FrameAdvance(uint64_t packed)
{
	(void)packed;
	g_audioFrames = 0;
	chimera_input_reads = 0;
	retro_run();
	g_frameCount++;
	g_inputRead = chimera_input_reads > 0;
}

ECL_EXPORT int InputWasRead(void) { return g_inputRead; }
ECL_EXPORT void SetRenderingEnabled(int on) { g_render = on != 0; }

ECL_EXPORT uint32_t *GetVideoBgra(void) { return g_picture; }
ECL_EXPORT int GetVideoWidth(void) { return g_width; }
ECL_EXPORT int GetVideoHeight(void) { return g_height; }
ECL_EXPORT int GetDisplayAspectX(void) { return 4; }
ECL_EXPORT int GetDisplayAspectY(void) { return 3; }
ECL_EXPORT int GetVsyncNumerator(void) { return (int)(g_fps * 1000.0 + 0.5); }
ECL_EXPORT int GetVsyncDenominator(void) { return 1000; }

ECL_EXPORT int16_t *GetAudio(void) { return g_audio; }
ECL_EXPORT int GetAudioSampleCount(void) { return g_audioFrames; }

ECL_EXPORT int GetMemoryDomainCount(void) { return g_memoryCount; }
ECL_EXPORT const char *GetMemoryDomainName(int i) { return i >= 0 && i < g_memoryCount ? g_memory[i].name : ""; }
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int i) { return i >= 0 && i < g_memoryCount ? g_memory[i].bytes : NULL; }
ECL_EXPORT int64_t GetMemoryDomainSize(int i) { return i >= 0 && i < g_memoryCount ? g_memory[i].size : 0; }
ECL_EXPORT int GetMemoryDomainWritable(int i) { return i >= 0 && i < g_memoryCount; }

ECL_EXPORT const int64_t *GetBusRanges(int32_t bus) { (void)bus; return NULL; }
ECL_EXPORT const uint8_t *ReadBus(int32_t bus, int64_t addr, int32_t len) { (void)bus; (void)addr; (void)len; return NULL; }
ECL_EXPORT void PokeBus(int32_t bus, int32_t addr, int32_t value) { (void)bus; (void)addr; (void)value; }

/* Export Save Data: the cartridge's save memory (EEPROM), when it has one */
ECL_EXPORT int32_t GetSaveDataFileCount(void) { return retro_get_memory_size(RETRO_MEMORY_SAVE_RAM) > 0 ? 1 : 0; }
ECL_EXPORT const char *GetSaveDataFileName(int32_t i) { return i == 0 ? "jaguar.eeprom" : ""; }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t i) { return i == 0 ? (int64_t)retro_get_memory_size(RETRO_MEMORY_SAVE_RAM) : 0; }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t i) { return i == 0 ? retro_get_memory_data(RETRO_MEMORY_SAVE_RAM) : NULL; }
