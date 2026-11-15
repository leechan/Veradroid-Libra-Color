#!/usr/bin/env python3
"""VeraDroid framework project (branch project/framework, docs/framework-project.md): framework-source changes that are
kept apart from the normal release line. Same rules as small-patches.py: exact string replacement, error when the old
text is not found. Every change here is inert unless the host creates its switch file in /dev/kfb, so an image built
with them behaves like the release image on an unchanged host.

Switch files (written by host/*/boot/lib/container.sh before Android starts):
  /dev/kfb/onepage   gralloc: both framebuffer pages are page 0 of /dev/kfb/fb (with hwcomposer.kindle.so)
  /dev/kfb/rgb565    SurfaceFlinger: opaque app windows get RGB 565 buffers instead of RGBA 8888
  /dev/kfb/noaudio   libmedia: AudioFlinger / AudioPolicy are absent on purpose: fail at once instead of waiting forever
"""
import sys, os
SRC = sys.argv[1]
PATCHES = [
    # 1a. one framebuffer page (framebuffer.cpp sets KFB_FLAG_ONEPAGE in private_module_t::flags): both buffers get
    #     offset 0. SurfaceFlinger / libagl still see two buffers (page flipping), they are just the same memory.
    ("hardware/libhardware/modules/gralloc/gralloc.cpp",
     "        vaddr += bufferSize;\n    }\n",
     "        if (!(m->flags & 0x00010000)) // VeraDroid: KFB_FLAG_ONEPAGE (framebuffer.cpp): every buffer is page 0\n"
     "            vaddr += bufferSize;\n    }\n"),
    # 1b. libagl copies the part of the old frame that was not redrawn into the new back buffer (swap rectangle). With one
    #     page the back buffer IS the front buffer: skip the self-copy (up to a full frame, 8.6 MB on a PW6, per GLES frame).
    ("frameworks/native/opengl/libagl/egl.cpp",
     "                    copyBlt(buffer, bits, previousBuffer, prevBits, copyBack);\n",
     "                    if (prevBits != bits) // VeraDroid: one framebuffer page, nothing to copy\n"
     "                        copyBlt(buffer, bits, previousBuffer, prevBits, copyBack);\n"),
    # 2. opaque window surfaces in RGB 565 (half the memory and half the bytes to draw / copy per frame). Only for
    #    window surfaces (WindowManager asks for OPAQUE / TRANSLUCENT and sets eOpaque for opaque windows), never for
    #    surfaces whose owner asked for an explicit format (SurfaceView, GL).
    ("frameworks/native/services/surfaceflinger/SurfaceFlinger_hwc1.cpp",
     "#include <stdint.h>\n",
     "#include <stdint.h>\n#include <unistd.h>\n"),
    ("frameworks/native/services/surfaceflinger/SurfaceFlinger_hwc1.cpp",
     "    // initialize the surfaces\n    switch (format) {\n    case PIXEL_FORMAT_TRANSPARENT:\n    case PIXEL_FORMAT_TRANSLUCENT:\n        format = PIXEL_FORMAT_RGBA_8888;\n        break;\n    case PIXEL_FORMAT_OPAQUE:\n        format = PIXEL_FORMAT_RGBX_8888;\n        break;\n    }\n",
     "    // initialize the surfaces\n    const bool vdWindowFormat = format == PIXEL_FORMAT_TRANSPARENT || format == PIXEL_FORMAT_TRANSLUCENT ||\n            format == PIXEL_FORMAT_OPAQUE;\n    switch (format) {\n    case PIXEL_FORMAT_TRANSPARENT:\n    case PIXEL_FORMAT_TRANSLUCENT:\n        format = PIXEL_FORMAT_RGBA_8888;\n        break;\n    case PIXEL_FORMAT_OPAQUE:\n        format = PIXEL_FORMAT_RGBX_8888;\n        break;\n    }\n"
     "    // VeraDroid (e-ink, 16 gray levels): opaque windows drawn in RGB 565 when the host asks for it\n"
     "    if (vdWindowFormat && (flags & ISurfaceComposerClient::eOpaque) && access(\"/dev/kfb/rgb565\", F_OK) == 0)\n"
     "        format = PIXEL_FORMAT_RGB_565;\n"),
    # 3. no audioserver: AudioSystem waits forever (0.5 s steps) for media.audio_flinger / media.audio_policy, and
    #    getService() itself waits 5 s each time. With /dev/kfb/noaudio we ask once with checkService() and from then on
    #    return null at once; every caller in libmedia already turns a null service into an error code
    #    (PERMISSION_DENIED / NO_INIT), which is what apps get today when audio does not work.
    ("frameworks/av/media/libmedia/AudioSystem.cpp",
     "// establish binder interface to AudioFlinger service\nconst sp<IAudioFlinger> AudioSystem::get_audio_flinger()\n{\n    sp<IAudioFlinger> af;\n    sp<AudioFlingerClient> afc;\n    {\n        Mutex::Autolock _l(gLock);\n        if (gAudioFlinger == 0) {\n            sp<IServiceManager> sm = defaultServiceManager();\n            sp<IBinder> binder;\n            do {\n",
     "// VeraDroid: the host started Android without audioserver (/dev/kfb/noaudio): never wait for it\n"
     "static int vd_noaudio_state = -1;   // -1 not checked yet, 0 audio expected, 1 no audioserver in this boot\n"
     "static bool vd_noaudio(const sp<IServiceManager>& sm, const char* name)\n{\n"
     "    if (vd_noaudio_state < 0) vd_noaudio_state = access(\"/dev/kfb/noaudio\", F_OK) == 0 ? 1 : 0;\n"
     "    if (vd_noaudio_state == 0) return false;\n"
     "    if (sm->checkService(String16(name)) != 0) return false;   // somebody started it after all: use it\n"
     "    return true;\n}\n\n"
     "// establish binder interface to AudioFlinger service\nconst sp<IAudioFlinger> AudioSystem::get_audio_flinger()\n{\n    sp<IAudioFlinger> af;\n    sp<AudioFlingerClient> afc;\n    {\n        Mutex::Autolock _l(gLock);\n        if (gAudioFlinger == 0) {\n            sp<IServiceManager> sm = defaultServiceManager();\n            sp<IBinder> binder;\n"
     "            if (vd_noaudio(sm, \"media.audio_flinger\")) return 0;\n            do {\n"),
    ("frameworks/av/media/libmedia/AudioSystem.cpp",
     "        if (gAudioPolicyService == 0) {\n            sp<IServiceManager> sm = defaultServiceManager();\n            sp<IBinder> binder;\n            do {\n",
     "        if (gAudioPolicyService == 0) {\n            sp<IServiceManager> sm = defaultServiceManager();\n            sp<IBinder> binder;\n"
     "            if (vd_noaudio(sm, \"media.audio_policy\")) return 0;\n            do {\n"),
    # 3b. AudioSystem.setErrorCallback() reports checkAudioFlinger() at once; DEAD_OBJECT makes AudioService retry
    #     "Audioserver died" every 500 ms for ever. With no audioserver on purpose there is nothing that died.
    ("frameworks/av/media/libmedia/AudioSystem.cpp",
     "/* static */ status_t AudioSystem::checkAudioFlinger()\n{\n",
     "/* static */ status_t AudioSystem::checkAudioFlinger()\n{\n"
     "    if (vd_noaudio(defaultServiceManager(), \"media.audio_flinger\")) return NO_ERROR;   // VeraDroid: absent on purpose\n"),
    # 3c. the other two services audioserver hosts: system_server's SoundTriggerHelper (listModules) and RadioService
    #     clients wait for them the same way (system_server never finishes booting).
    ("frameworks/av/soundtrigger/SoundTrigger.cpp",
     "        sp<IServiceManager> sm = defaultServiceManager();\n        sp<IBinder> binder;\n        do {\n            binder = sm->getService(String16(kSoundTriggerHwServiceName));\n",
     "        sp<IServiceManager> sm = defaultServiceManager();\n        sp<IBinder> binder;\n"
     "        if (access(\"/dev/kfb/noaudio\", F_OK) == 0 && sm->checkService(String16(kSoundTriggerHwServiceName)) == 0)\n"
     "            return 0;   // VeraDroid: no audioserver on purpose (/dev/kfb/noaudio): never wait\n"
     "        do {\n            binder = sm->getService(String16(kSoundTriggerHwServiceName));\n"),
    ("frameworks/av/soundtrigger/SoundTrigger.cpp",
     "#include <utils/Log.h>\n",
     "#include <utils/Log.h>\n#include <unistd.h>\n"),
    ("frameworks/av/radio/Radio.cpp",
     "        sp<IServiceManager> sm = defaultServiceManager();\n        sp<IBinder> binder;\n        do {\n            binder = sm->getService(String16(kRadioServiceName));\n",
     "        sp<IServiceManager> sm = defaultServiceManager();\n        sp<IBinder> binder;\n"
     "        if (access(\"/dev/kfb/noaudio\", F_OK) == 0 && sm->checkService(String16(kRadioServiceName)) == 0)\n"
     "            return 0;   // VeraDroid: no audioserver on purpose (/dev/kfb/noaudio): never wait\n"
     "        do {\n            binder = sm->getService(String16(kRadioServiceName));\n"),
    ("frameworks/av/radio/Radio.cpp",
     "#include <utils/Log.h>\n",
     "#include <utils/Log.h>\n#include <unistd.h>\n"),
    ("frameworks/av/media/libmedia/AudioSystem.cpp",
     "#include <math.h>\n",
     "#include <math.h>\n#include <unistd.h>\n"),
]
for rel, old, new in PATCHES:
    p = os.path.join(SRC, rel)
    s = open(p, encoding="utf-8").read()
    if new in s:
        print("already patched:", rel); continue
    if old not in s:
        print("ERROR: text not found in", rel); sys.exit(1)
    open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
    print("patched:", rel)
