/* FBInk stand-in for the native legacy veradroid-epd test (tests/legacy-epd-test.sh): an i.MX EPDC Kindle (PW4 "Rex",
   not MediaTek), no panel. Every refresh is logged by epd.c itself; fbink_wait_for_complete sleeps for the waveform's
   time as FBInk's fbink.h lists it for the i.MX EPDC (A2 ~120 ms, DU ~260 ms, the 16-gray ones ~450 ms) so the
   "one update in flight" pacing and the busy logic run as on a device. Not real panel timing. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "fbink.h"
static uint32_t last_marker = 0;
static int last_us = 0;
int fbink_open(void) { return open("/dev/null", O_RDWR); }
int fbink_close(int fd) { return close(fd); }
int fbink_init(int fd, const FBInkConfig *restrict c) { (void)fd; (void)c; return 0; }
void fbink_get_state(const FBInkConfig *restrict c, FBInkState *restrict s)
{
    (void)c; memset(s, 0, sizeof(*s));
    s->is_mtk = 0; s->screen_width = 1272; s->screen_height = 1696; s->bpp = 8;
    const char *p = getenv("STUB_PLATFORM");
    snprintf((char *)s->device_platform, sizeof(s->device_platform), "%s", p ? p : "Rex");
}
int fbink_print_raw_data(int fd, const unsigned char *restrict d, const int w, const int h, const size_t len, short x, short y,
                         const FBInkConfig *restrict c)
{
    (void)fd; (void)d; (void)w; (void)h; (void)len; (void)x; (void)y;
    last_marker++;
    last_us = c->wfm_mode == WFM_A2 ? 120000 : c->wfm_mode == WFM_DU ? 260000 : 450000;
    /* the dithering request the refresh carried, for the A2 / monochrome check */
    fprintf(stderr, "stub: wfm=%d dither=%d\n", (int)c->wfm_mode, (int)c->dithering_mode);
    return 0;
}
int fbink_wait_for_complete(int fd, uint32_t m) { (void)fd; (void)m; usleep(last_us); return 0; }
uint32_t fbink_get_last_marker(void) { return last_marker; }
int fbink_mtk_set_swipe_data(MTK_SWIPE_DIRECTION_INDEX_T d, uint8_t s) { (void)d; (void)s; return 0; }
