// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * noduck: a VLC 3.0 interface plugin that keeps VLC at full volume while a call ducks other audio.
 *
 * The audio server never ducks a process that holds a duck request of its own. On load the plugin registers a
 * 0.999 duck (-0.01 dB, inaudible) on every output device, and again on devices that appear later. The request
 * goes away with VLC.
 *
 * Only the plugin descriptor protocol of vlc_plugin.h (3.0) is used, no libvlccore calls, so the plugin builds
 * without the VLC SDK.
 */
#include <CoreAudio/CoreAudio.h>
#include <os/log.h>
#include <stddef.h>

#define NODUCK_LEVEL 0.999f

typedef int (*vlc_set_cb)(void *, void *, int, ...);

/* enum vlc_module_properties, vlc_plugin.h 3.0.x */
enum {
    VLC_MODULE_CREATE = 0,
    VLC_MODULE_SHORTCUT = 0x101, VLC_MODULE_CAPABILITY, VLC_MODULE_SCORE, VLC_MODULE_CB_OPEN, VLC_MODULE_CB_CLOSE,
    VLC_MODULE_NO_UNLOAD, VLC_MODULE_NAME, VLC_MODULE_SHORTNAME, VLC_MODULE_DESCRIPTION,
};

/* Private CoreAudio function: exported, not in the public headers. */
extern OSStatus AudioDeviceDuck(AudioObjectID, Float32, const AudioTimeStamp *, Float32);

static os_log_t log_handle;
static const AudioObjectPropertyAddress devices_address = {
    kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
};

static int has_output(AudioObjectID device) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain };
    UInt32 size = 0;
    return AudioObjectGetPropertyDataSize(device, &a, 0, NULL, &size) == noErr && size > 0;
}

static void duck_all(float level) {
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &devices_address, 0, NULL, &size) || size == 0) return;
    AudioObjectID ids[128];
    if (size > sizeof ids) size = sizeof ids;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &devices_address, 0, NULL, &size, ids)) return;
    for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
        if (!has_output(ids[i])) continue;
        OSStatus status = AudioDeviceDuck(ids[i], level, NULL, 0.0f);
        os_log(log_handle, "noduck: AudioDeviceDuck(%u, %.3f) = %d", ids[i], level, (int)status);
    }
}

static OSStatus devices_changed(AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress *addresses, void *context) {
    duck_all(NODUCK_LEVEL);   /* registering a device again is harmless */
    return noErr;
}

static int Open(void *object) {
    log_handle = os_log_create("io.github.anegoda1995.shuttheduckoff", "noduck");
    duck_all(NODUCK_LEVEL);
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &devices_address, devices_changed, NULL);
    os_log(log_handle, "noduck: active, VLC is exempt from other apps' ducking");
    return 0;   /* VLC_SUCCESS */
}

static void Close(void *object) {
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &devices_address, devices_changed, NULL);
    duck_all(1.0f);
    os_log(log_handle, "noduck: stopped");
}

__attribute__((visibility("default")))
int vlc_entry__3_0_0f(vlc_set_cb vlc_set, void *opaque) {
    void *module = NULL;
    if (vlc_set(opaque, NULL, VLC_MODULE_CREATE, &module)) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_NAME, "noduck")) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_SHORTNAME, "No duck")) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_DESCRIPTION, "Keep VLC at full volume while calls duck other audio")) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_CAPABILITY, "interface")) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_SCORE, 0)) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_CB_OPEN, "Open", (void *)Open)) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_CB_CLOSE, "Close", (void *)Close)) return -1;
    if (vlc_set(opaque, module, VLC_MODULE_NO_UNLOAD)) return -1;   /* keeps the CoreAudio listener valid */
    return 0;
}

__attribute__((visibility("default"))) const char *vlc_entry_copyright__3_0_0f(void) { return "Copyright (C) 2026 anegoda1995"; }
__attribute__((visibility("default"))) const char *vlc_entry_license__3_0_0f(void) { return "GPLv3+"; }
