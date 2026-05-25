/*
 * stremio-mpv-shim.c -- LD_PRELOAD shim for the Stremio Flatpak's embedded libmpv.
 *
 * Stremio's shell never enables mpv config-file loading and exposes no video
 * settings, so its embedded mpv runs the default video-sync=audio. Against
 * 23.976 fps content on a 144 Hz panel that yields periodic cadence judder
 * (the user's "looks like a game with no vsync"). libmpv is dynamically linked
 * (NEEDED libmpv.so.1; mpv_initialize / mpv_set_option_string are imported UND
 * symbols), so we interpose mpv_initialize() and push the options in just before
 * the real initialization runs -- mpv requires these to be set pre-init.
 *
 * Applied via a flatpak override (see ../home/stremio.nix):
 *   flatpak override --user com.stremio.Stremio \
 *     --filesystem=<dir>:ro --env=LD_PRELOAD=<dir>/shim.so
 *
 * Uses only ancient libc symbols (dlsym), so a normal nixpkgs build loads inside
 * the Stremio runtime org.kde.Platform//5.15-24.08 (glibc 2.39). Safe by design:
 * if libmpv ever rejects an option the return code is ignored and the real
 * mpv_initialize still runs, so playback never breaks -- it just loses the tweak.
 *
 * Build: $CC -shared -fPIC -O2 -o shim.so stremio-mpv-shim.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>

typedef int (*mpv_initialize_t)(void *);
typedef int (*mpv_set_option_string_t)(void *, const char *, const char *);

int mpv_initialize(void *ctx) {
    mpv_initialize_t real_init =
        (mpv_initialize_t) dlsym(RTLD_NEXT, "mpv_initialize");
    mpv_set_option_string_t set_opt =
        (mpv_set_option_string_t) dlsym(RTLD_NEXT, "mpv_set_option_string");

    if (set_opt) {
        /* Resample audio (~0.1%, inaudible) to the display clock so each
         * 23.976 fps frame is shown for an even number of refreshes, then
         * interpolate in-between frames up to the 144 Hz display rate so pans
         * are smooth (tscale=mitchell = full motion interpolation, the look
         * confirmed preferred over the steppy 24 fps cadence). */
        set_opt(ctx, "video-sync", "display-resample");
        set_opt(ctx, "interpolation", "yes");
        set_opt(ctx, "tscale", "mitchell");
    }

    return real_init ? real_init(ctx) : -1;
}
