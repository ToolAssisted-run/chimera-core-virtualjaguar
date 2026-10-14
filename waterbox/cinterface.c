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

/* What a core must never do, whatever a project says: reach the network,
 * the microphone or a debugger, read or write folders of textures or an SD
 * card, or skip drawing frames. */
static const struct { const char *key, *value; } kForced[] = {
	{ "virtualjaguar_netlink", "disabled" },
	{ "virtualjaguar_voice_chat", "disabled" },
	{ "virtualjaguar_gdb_stub", "disabled" },
	{ "virtualjaguar_texture_dump", "disabled" },
	{ "virtualjaguar_texture_replace", "disabled" },
	{ "virtualjaguar_jgd_sd", "disabled" },
	{ "virtualjaguar_frameskip", "disabled" },
	{ "virtualjaguar_alt_inputs", "disabled" },
};

static void take_option(const char *key, const char *def)
{
	if (!key || g_optionCount >= MAX_OPTIONS) return;
	for (size_t i = 0; i < sizeof kForced / sizeof kForced[0]; i++)
		if (!strcmp(kForced[i].key, key))
		{
			g_options[g_optionCount].key = key;
			snprintf(g_options[g_optionCount].value, sizeof g_options[g_optionCount].value, "%s", kForced[i].value);
			g_optionCount++;
			return;
		}
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
 * What is in each of the two ports is a setting (p1_device, p2_device, as
 * Virtual Jaguar names them). Pads - one in a port, or four behind a Team
 * Tap - go into the Jaguar's own button tables (joystick.c) at the end of
 * the libretro layer's input step (patch 0002), so its RetroPad mapping is
 * given nothing for them. The other controllers are modelled by Virtual
 * Jaguar's input layer, which asks the frontend through libretro for a
 * mouse's movement, a stick's place, a light gun's aim; input_state()
 * answers those from the project's controls. Players: port 1 holds P1, and
 * behind a Team Tap P3, P4 and P5; port 2 holds P2, and P6, P7 and P8. */
static const struct { const char *name; int button; } kPad[] = {
	{ "Up", BUTTON_U }, { "Down", BUTTON_D }, { "Left", BUTTON_L }, { "Right", BUTTON_R },
	{ "A", BUTTON_A }, { "B", BUTTON_B }, { "C", BUTTON_C }, { "Option", BUTTON_OPTION }, { "Pause", BUTTON_PAUSE },
	{ "1", BUTTON_1 }, { "2", BUTTON_2 }, { "3", BUTTON_3 }, { "4", BUTTON_4 }, { "5", BUTTON_5 }, { "6", BUTTON_6 },
	{ "7", BUTTON_7 }, { "8", BUTTON_8 }, { "9", BUTTON_9 }, { "*", BUTTON_s }, { "0", BUTTON_0 }, { "#", BUTTON_d },
};
#define PAD_BUTTONS ((int)(sizeof kPad / sizeof kPad[0]))
#define PLAYERS 8
/* a port's extra buttons, after the eight players' pads */
enum { kD, kE, kF, kG, kRezero, kMouseLeft, kMouseRight, kTrigger, kAuxA, kAuxB, kGunStart, kGunSelect, kOffscreen, kExtra };
static const char *const kExtraNames[kExtra] = {
	"D", "E", "F", "G", "Rezero", "Mouse Left", "Mouse Right",
	"Trigger", "Aux A", "Aux B", "Gun Start", "Gun Select", "Gun Offscreen",
};
#define PAD_BASE 0
#define EXTRA_BASE (PLAYERS * PAD_BUTTONS)
#define BUTTON_COUNT (EXTRA_BASE + 2 * kExtra)
/* a port's axes */
enum { kSpinner, kMouseX, kMouseY, kStickX, kStickY, k6dZ, k6dTX, k6dTY, k6dTZ, kGunX, kGunY, kPortAxes };
static const char *const kAxisNames[kPortAxes] = {
	"Spinner", "Mouse X", "Mouse Y", "Stick X", "Stick Y", "6D Z", "6D TX", "6D TY", "6D TZ", "Gun X", "Gun Y",
};
#define AXIS_COUNT (2 * kPortAxes)
static char g_buttonNames[BUTTON_COUNT][24];
static char g_axisNames[AXIS_COUNT][24];
static int g_held[BUTTON_COUNT];
static int g_axis[AXIS_COUNT];
static int g_inputRead;
extern int chimera_input_reads;   /* joystick.c (patch 0003) */

/* what is in each port */
enum { kPadDev, kTeamTap, kRotary, kMouse, kAnalog, kDriving, kPaddle, k6D, kGun };
static int g_device[2];

static int device_setting(const char *name)
{
	char v[32] = "pad";
	wbx_setting_str(name, v, sizeof v);
	if (!strcmp(v, "teamtap")) return kTeamTap;
	if (!strcmp(v, "rotary")) return kRotary;
	if (!strncmp(v, "mouse", 5)) return kMouse;
	if (!strcmp(v, "analog")) return kAnalog;
	if (!strcmp(v, "driving")) return kDriving;
	if (!strcmp(v, "paddle")) return kPaddle;
	if (!strcmp(v, "6d")) return k6D;
	if (!strcmp(v, "lightgun")) return kGun;
	return kPadDev;
}

/* player p (0-7) is in port p's... port 0 holds players 0, 2, 3, 4 and
 * port 1 holds 1, 5, 6, 7; the socket is the place behind the Team Tap */
static int port_of(int player) { return player == 0 || (player >= 2 && player <= 4) ? 0 : 1; }
static int socket_of(int player) { return player <= 1 ? 0 : player <= 4 ? player - 1 : player - 4; }

static int pad_held(int player, int b) { return g_held[PAD_BASE + player * PAD_BUTTONS + b]; }
static int extra_held(int port, int e) { return g_held[EXTRA_BASE + port * kExtra + e]; }
static int axis_value(int port, int a) { return g_axis[port * kPortAxes + a]; }

/* is button i of the panel live, given what is in the ports? */
static int button_active(int i)
{
	if (i < EXTRA_BASE)
	{
		int player = i / PAD_BUTTONS, b = i % PAD_BUTTONS, port = port_of(player), dev = g_device[port];
		if (socket_of(player) > 0) return dev == kTeamTap;
		switch (dev)
		{
		case kPadDev: case kTeamTap: case kPaddle: return 1;
		case kRotary: return b > 3;   /* the wheel takes the place of the pad's directions */
		case kAnalog: case kDriving: return b <= 6;   /* the hat and A, B, C */
		case k6D: return b >= 4 && b <= 6;   /* A, B, C */
		default: return 0;
		}
	}
	int port = (i - EXTRA_BASE) / kExtra, e = (i - EXTRA_BASE) % kExtra, dev = g_device[port];
	switch (e)
	{
	case kD: return dev == kAnalog || dev == kDriving || dev == k6D;
	case kE: case kF: case kG: case kRezero: return dev == k6D;
	case kMouseLeft: case kMouseRight: return dev == kMouse;
	default: return dev == kGun;
	}
}

static int axis_active(int i)
{
	int port = i / kPortAxes, a = i % kPortAxes, dev = g_device[port];
	switch (a)
	{
	case kSpinner: return dev == kRotary;
	case kMouseX: case kMouseY: return dev == kMouse;
	case kStickX: case kStickY: return dev == kAnalog || dev == kDriving || dev == kPaddle || dev == k6D;
	case kGunX: case kGunY: return dev == kGun;
	default: return dev == k6D;
	}
}

void chimera_fill_joypads(void)
{
	for (int player = 0; player < PLAYERS; player++)
	{
		int port = port_of(player), dev = g_device[port], sock = socket_of(player);
		if (sock > 0 && dev != kTeamTap) continue;
		if (dev != kPadDev && dev != kTeamTap && dev != kPaddle && dev != kRotary) continue;
		uint8_t *table = port == 0 ? joypad0Buttons : joypad1Buttons;
		for (int b = 0; b < PAD_BUTTONS; b++)
		{
			if (dev == kRotary && b <= 3) continue;
			if (pad_held(player, b)) table[sock * JOYPAD_SOCKET_SLOTS + kPad[b].button] = 0xff;
		}
	}
}

/* the libretro layer's questions about a controller other than a pad */
static int16_t controller_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
	if (port > 1) return 0;
	int dev = g_device[port];
	int player = (int)port;   /* P1 or P2: socket 0 */
	switch (device & RETRO_DEVICE_MASK)
	{
	case RETRO_DEVICE_JOYPAD:
		/* the switches of the analog, driving and 6D controllers */
		if (dev != kAnalog && dev != kDriving && dev != k6D) return 0;
		switch (id)
		{
		case RETRO_DEVICE_ID_JOYPAD_A: return pad_held(player, 4);
		case RETRO_DEVICE_ID_JOYPAD_B: return pad_held(player, 5);
		case RETRO_DEVICE_ID_JOYPAD_Y: return pad_held(player, 6);
		case RETRO_DEVICE_ID_JOYPAD_X: return extra_held(port, kD);
		case RETRO_DEVICE_ID_JOYPAD_UP: return dev != k6D && pad_held(player, 0);
		case RETRO_DEVICE_ID_JOYPAD_DOWN: return dev != k6D && pad_held(player, 1);
		case RETRO_DEVICE_ID_JOYPAD_LEFT: return dev != k6D && pad_held(player, 2);
		case RETRO_DEVICE_ID_JOYPAD_RIGHT: return dev != k6D && pad_held(player, 3);
		case RETRO_DEVICE_ID_JOYPAD_L3: return dev == k6D && extra_held(port, kE);
		case RETRO_DEVICE_ID_JOYPAD_R3: return dev == k6D && extra_held(port, kF);
		case RETRO_DEVICE_ID_JOYPAD_START: return dev == k6D && extra_held(port, kG);
		case RETRO_DEVICE_ID_JOYPAD_SELECT: return dev == k6D && extra_held(port, kRezero);
		default: return 0;
		}
	case RETRO_DEVICE_MOUSE:
		if (dev == kRotary) return id == RETRO_DEVICE_ID_MOUSE_X ? (int16_t)axis_value(port, kSpinner) : 0;
		if (dev != kMouse) return 0;
		switch (id)
		{
		case RETRO_DEVICE_ID_MOUSE_X: return (int16_t)axis_value(port, kMouseX);
		case RETRO_DEVICE_ID_MOUSE_Y: return (int16_t)axis_value(port, kMouseY);
		case RETRO_DEVICE_ID_MOUSE_LEFT: return extra_held(port, kMouseLeft);
		case RETRO_DEVICE_ID_MOUSE_RIGHT: return extra_held(port, kMouseRight);
		default: return 0;
		}
	case RETRO_DEVICE_ANALOG:
		if (dev != kAnalog && dev != kDriving && dev != kPaddle && dev != k6D) return 0;
		if (index == RETRO_DEVICE_INDEX_ANALOG_LEFT)
			return (int16_t)axis_value(port, id == RETRO_DEVICE_ID_ANALOG_X ? kStickX : kStickY);
		if (index == RETRO_DEVICE_INDEX_ANALOG_RIGHT && dev == k6D)
			return (int16_t)axis_value(port, id == RETRO_DEVICE_ID_ANALOG_X ? k6dTX : k6dTZ);
		if (index == RETRO_DEVICE_INDEX_ANALOG_BUTTON && dev == k6D)
		{
			/* Z is R2 - L2 and TY is R - L in the layer's reading */
			int z = axis_value(port, k6dZ), ty = axis_value(port, k6dTY);
			switch (id)
			{
			case RETRO_DEVICE_ID_JOYPAD_R2: return (int16_t)(z > 0 ? z : 0);
			case RETRO_DEVICE_ID_JOYPAD_L2: return (int16_t)(z < 0 ? -z : 0);
			case RETRO_DEVICE_ID_JOYPAD_R: return (int16_t)(ty > 0 ? ty : 0);
			case RETRO_DEVICE_ID_JOYPAD_L: return (int16_t)(ty < 0 ? -ty : 0);
			default: return 0;
			}
		}
		return 0;
	case RETRO_DEVICE_LIGHTGUN:
		if (dev != kGun) return 0;
		switch (id)
		{
		/* Chimera's pointer is a fraction of the picture, 0 to 65535;
		 * libretro's is -32768 to 32767 across it */
		case RETRO_DEVICE_ID_LIGHTGUN_SCREEN_X: return (int16_t)(axis_value(port, kGunX) - 32768);
		case RETRO_DEVICE_ID_LIGHTGUN_SCREEN_Y: return (int16_t)(axis_value(port, kGunY) - 32768);
		case RETRO_DEVICE_ID_LIGHTGUN_TRIGGER: return extra_held(port, kTrigger);
		case RETRO_DEVICE_ID_LIGHTGUN_AUX_A: return extra_held(port, kAuxA);
		case RETRO_DEVICE_ID_LIGHTGUN_AUX_B: return extra_held(port, kAuxB);
		case RETRO_DEVICE_ID_LIGHTGUN_START: return extra_held(port, kGunStart);
		case RETRO_DEVICE_ID_LIGHTGUN_SELECT: return extra_held(port, kGunSelect);
		case RETRO_DEVICE_ID_LIGHTGUN_IS_OFFSCREEN: return extra_held(port, kOffscreen);
		default: return 0;
		}
	default:
		return 0;
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

/* The libretro layer's own RetroPad mapping is given nothing for a pad (the
 * pads reach the Jaguar's tables directly, chimera_fill_joypads); the
 * other controllers' questions are answered by controller_state. */
static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
	return controller_state(port, device, index, id);
}

/* ---- the memory --------------------------------------------------------- */
struct memory_area { const char *name; uint8_t *bytes; int64_t size; };
static struct memory_area g_memory[4];
static int g_memoryCount;

/* ---- the files ---------------------------------------------------------- */
static char g_game[512];
static int g_cd;   /* a Jaguar CD: the disc is read by its name, as upstream wants */

/* the save file a project starts from: the Save data slot's file (an
 * exported .eeprom or .memtrack, or a RetroArch .srm) */
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

static int finish_init(void);

ECL_EXPORT int Init(void)
{
	g_loadError[0] = '\0';
	/* the Machine setting: a cartridge console, or one with the Jaguar CD */
	char machine[32] = "jaguar";
	wbx_setting_str("machine", machine, sizeof machine);
	g_cd = !strcmp(machine, "jaguarcd");
	const char *slot = g_cd ? "disc" : "cart";
	if (wbx_slot_count(slot) > 0)
		wbx_slot_name(slot, 0, g_game, sizeof g_game);
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
	for (int p = 0; p < PLAYERS; p++)
		for (int i = 0; i < PAD_BUTTONS; i++)
			snprintf(g_buttonNames[PAD_BASE + p * PAD_BUTTONS + i], sizeof g_buttonNames[0], "P%d %s", p + 1, kPad[i].name);
	for (int port = 0; port < 2; port++)
	{
		for (int e = 0; e < kExtra; e++)
			snprintf(g_buttonNames[EXTRA_BASE + port * kExtra + e], sizeof g_buttonNames[0], "P%d %s", port + 1, kExtraNames[e]);
		for (int a = 0; a < kPortAxes; a++)
			snprintf(g_axisNames[port * kPortAxes + a], sizeof g_axisNames[0], "P%d %s", port + 1, kAxisNames[a]);
	}
	g_device[0] = device_setting("p1_device");
	g_device[1] = device_setting("p2_device");
	if (g_device[0] == kMouse) g_device[0] = kPadDev;   /* the mice go in port 2 */
	if (g_device[1] == kGun) g_device[1] = kPadDev;     /* the light gun in port 1 */
	g_frameCount = 0;

	retro_set_environment(environment);
	retro_set_video_refresh(video_refresh);
	retro_set_audio_sample(audio_sample);
	retro_set_audio_sample_batch(audio_batch);
	retro_set_input_poll(input_poll);
	retro_set_input_state(input_state);
	retro_init();
	if (getenv("CHIMERA_VJ_OPTIONS"))
		for (int i = 0; i < g_optionCount; i++)
			fprintf(stderr, "option %s=%s\n", g_options[i].key, g_options[i].value);

	if (g_cd)
	{
		struct retro_game_info disc = { g_game, NULL, 0, NULL };
		if (!retro_load_game(&disc))
		{
			snprintf(g_loadError, sizeof g_loadError, "the emulator did not start with the disc %s", g_game);
			return 0;
		}
		return finish_init();
	}

	/* a cartridge is read here and handed over whole */
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
	return finish_init();
}

/* after the game is loaded: the rate, the save memory, the memory domains */
static int finish_init(void)
{
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
ECL_EXPORT int IsButtonActive(int32_t i) { return i >= 0 && i < BUTTON_COUNT && button_active(i); }
ECL_EXPORT void SetButton(int32_t i, int32_t state)
{
	if (i >= 0 && i < BUTTON_COUNT) g_held[i] = state != 0;
}

ECL_EXPORT int GetAxisCount(void) { return AXIS_COUNT; }
ECL_EXPORT const char *GetAxisName(int32_t i) { return i >= 0 && i < AXIS_COUNT ? g_axisNames[i] : ""; }
ECL_EXPORT int IsAxisActive(int32_t i) { return i >= 0 && i < AXIS_COUNT && axis_active(i); }
ECL_EXPORT void SetAxis(int32_t i, int32_t value)
{
	if (i < 0 || i >= AXIS_COUNT) return;
	int a = i % kPortAxes;
	int lo = -32768, hi = 32767;
	if (a == kSpinner || a == kMouseX || a == kMouseY) { lo = -128; hi = 127; }
	if (a == kGunX || a == kGunY) { lo = 0; hi = 65535; }
	g_axis[i] = value < lo ? lo : value > hi ? hi : value;
}

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

/* Export Save Data: the machine's save memory, when it has one */
ECL_EXPORT int32_t GetSaveDataFileCount(void) { return retro_get_memory_size(RETRO_MEMORY_SAVE_RAM) > 0 ? 1 : 0; }
/* a cartridge console's is its EEPROM; a CD console's also holds the
 * Memory Track's */
ECL_EXPORT const char *GetSaveDataFileName(int32_t i) { return i == 0 ? (g_cd ? "jaguarcd.memtrack" : "jaguar.eeprom") : ""; }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t i) { return i == 0 ? (int64_t)retro_get_memory_size(RETRO_MEMORY_SAVE_RAM) : 0; }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t i) { return i == 0 ? retro_get_memory_data(RETRO_MEMORY_SAVE_RAM) : NULL; }
