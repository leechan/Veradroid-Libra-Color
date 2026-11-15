// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * hwcomposer.kindle: a software hardware-composer for VeraDroid's virtual e-ink framebuffer.
 *
 * Why: without a HWC SurfaceFlinger composes every frame with the software GLES (libagl / PixelFlinger) and then swaps
 * with a copy-back. Measured on a Paperwhite 6 (2 x Cortex-A53, 1272x1696): 35-65 ms of CPU per composed frame, on the
 * main thread of SurfaceFlinger - that is added to every touch-to-screen path and it takes one of the two cores whenever
 * an app animates or scrolls. Almost every frame is "one opaque full-screen window + a thin status bar", which is a plain
 * copy. This HAL takes those frames as overlays and writes the layers itself into /dev/kfb/fb (the same file the default
 * gralloc framebuffer uses), row by row and only the rows that differ from what is there, then tells veradroid-epd
 * which rows changed ("P <page> <first row> <end row>"; the framebuffer HAL only said "P <page>"). A frame that changes
 * nothing (apps post those all the time: invisible spinners, cursors) costs one compare here and nothing in the bridge.
 * Anything it does not understand (scaled / rotated / dim / skip layers, odd buffers) goes back to GLES for that frame.
 *
 * It also provides the vsync (SurfaceFlinger does not start its fake vsync thread when a HWC is present): period from
 * /dev/kfb/hz (default 30).
 *
 * Switches (files in /dev/kfb, written by the host):
 *   hwc.off    at open: refuse to load -> SurfaceFlinger uses the framebuffer HAL as before
 *   onepage    at open (framework project, docs/framework-project.md): the patched gralloc gives SurfaceFlinger two
 *              framebuffer "pages" that are the same memory (page 0 of /dev/kfb/fb). GLES frames are then drawn straight
 *              into the picture the bridge reads, overlay frames are written there too, and page 1 is never touched
 *              (tmpfs: it costs no memory). No page sync is needed when switching between GLES and overlay frames.
 *   hwc.gles   checked at run time: never take overlays (GLES composition, only vsync and posting come from here)
 *   hz         refresh rate for vsync, 10..60
 *
 * Buffers come from the default gralloc (hardware/libhardware/modules/gralloc): its handle has no width / height / format,
 * so the layer geometry is checked against the handle's size (stride = width rounded up to 2, 32 bpp) and everything
 * that does not match is left to GLES.
 */
#define LOG_TAG "hwc_kindle"
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <cutils/log.h>
#include <hardware/hardware.h>
#include <hardware/hwcomposer.h>

#define KFB_FILE "/dev/kfb/fb"
#define KFB_INFO "/dev/kfb/info"
#define KFB_FIFO "/dev/kfb/epd.fifo"
#define KFB_OFF  "/dev/kfb/hwc.off"
#define KFB_GLES "/dev/kfb/hwc.gles"
#define KFB_HZ   "/dev/kfb/hz"
#define KFB_PAGE "/dev/kfb/page"
#define KFB_ONEPAGE "/dev/kfb/onepage"

/* the default gralloc's private_handle_t (gralloc_priv.h), C view */
struct vd_handle {
    native_handle_t nh;
    int fd;
    int magic;
    int flags;
    int size;
    int offset;
    uint64_t base __attribute__((aligned(8)));
    int pid;
};
#define VD_MAGIC 0x3141592
#define VD_FLAG_FB 1

struct ctx {
    hwc_composer_device_1_t dev;
    const hwc_procs_t *procs;
    int w, h;
    uint8_t *fb;              /* 2 pages of RGBX */
    size_t page_bytes;
    int fifo;
    int last_page;            /* the page veradroid-epd was told about last */
    int ovl_since_gles;       /* an overlay frame was drawn since the last GLES frame: the pages differ */
    int overlay;              /* decision of the last prepare() */
    int force_gles;
    int page_noted;
    int lost;                 /* an announcement to the bridge was not delivered */
    time_t force_checked;
    long period_ns;
    pthread_t vthread;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    int vsync_on;
    int onepage;              /* /dev/kfb/onepage: both framebuffer pages are page 0 (see the header) */
    unsigned long n_ovl, n_gles, n_sync, n_same;
    uint32_t *rowbuf;         /* one composed row */
    long last_us, max_us;
};

static long long now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

static void notify(struct ctx *c, int page, int y0, int y1)
{
    c->last_page = page;
    if (page != c->page_noted) {          /* for a bridge that is started later: which page holds the picture */
        int pfd = open(KFB_PAGE, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
        if (pfd >= 0) { char b = (char)('0' + page); if (write(pfd, &b, 1) == 1) c->page_noted = page; close(pfd); }
    }
    if (c->fifo < 0) {
        c->fifo = open(KFB_FIFO, O_WRONLY | O_NONBLOCK | O_CLOEXEC);
        if (c->fifo < 0) { c->lost = 1; return; }      /* the bridge is not running (yet): drop the update */
    }
    /* the bridge only looks at the rows we name. If an announcement did not get through, the next one names no rows:
       the bridge then compares the whole page again. */
    char msg[40];
    int n = (y1 > y0 && !c->lost) ? snprintf(msg, sizeof(msg), "P %d %d %d\n", page, y0, y1) : snprintf(msg, sizeof(msg), "P %d\n", page);
    if (write(c->fifo, msg, n) != n) {
        c->lost = 1;
        if (errno != EAGAIN) { close(c->fifo); c->fifo = -1; }
    } else c->lost = 0;
}

static size_t page_round(size_t v) { return (v + 4095) & ~(size_t)4095; }

/* can we copy this layer ourselves? fills the buffer stride (pixels); *bpp = 4 (RGBA / RGBX 8888) or 2 (RGB 565) */
static int layer_ok2(const struct ctx *c, const hwc_layer_1_t *l, int *stride, int *bpp)
{
    if (l->flags & HWC_SKIP_LAYER) return 0;
    if (l->compositionType == HWC_BACKGROUND || l->compositionType == HWC_SIDEBAND) return 0;
    if (!l->handle) return 0;
    if (l->transform != 0) return 0;
    if (l->blending != HWC_BLENDING_NONE && l->blending != HWC_BLENDING_PREMULT) return 0;
    const struct vd_handle *h = (const struct vd_handle *)l->handle;
    if (h->nh.numFds != 1 || h->magic != VD_MAGIC || (h->flags & VD_FLAG_FB) || !h->base) return 0;
    const hwc_rect_t *s = &l->sourceCropi, *d = &l->displayFrame;
    int sw = s->right - s->left, sh = s->bottom - s->top;
    if (sw <= 0 || sh <= 0 || s->left < 0 || s->top < 0) return 0;
    if (sw != d->right - d->left || sh != d->bottom - d->top) return 0;      /* scaled */
    /* the buffer is as large as the crop says (crop from 0,0): gralloc_alloc() made it
       align(h, 2) * align(w, 2) * 4 + 4 bytes, rounded up to a page */
    if (s->left != 0 || s->top != 0) return 0;
    int st = (s->right + 1) & ~1, bh = (s->bottom + 1) & ~1;
    int b;
    if (page_round((size_t)bh * st * 4 + 4) == (size_t)h->size) b = 4;
    else if (page_round((size_t)bh * st * 2 + 4) == (size_t)h->size && l->blending == HWC_BLENDING_NONE) b = 2;   /* 565: opaque */
    else return 0;
    (void)c;
    *stride = st;
    if (bpp) *bpp = b;
    return 1;
}
static int layer_ok(const struct ctx *c, const hwc_layer_1_t *l, int *stride) { int b; return layer_ok2(c, l, stride, &b); }

static inline void row565(uint32_t *d, const uint16_t *s, int w)
{
    for (int x = 0; x < w; x++) {
        uint32_t p = s[x];
        uint32_t r = (p >> 11) & 31, g = (p >> 5) & 63, b = p & 31;
        r = (r << 3) | (r >> 2); g = (g << 2) | (g >> 4); b = (b << 3) | (b >> 2);
        d[x] = 0xff000000u | (b << 16) | (g << 8) | r;          /* bytes R, G, B, X */
    }
}

static inline uint32_t blend_px(uint32_t s, uint32_t d)
{
    uint32_t ia = 255 - (s >> 24);
    uint32_t rb = (d & 0x00ff00ffu) * ia + 0x00800080u;
    rb = ((rb + ((rb >> 8) & 0x00ff00ffu)) >> 8) & 0x00ff00ffu;
    uint32_t ag = ((d >> 8) & 0x00ff00ffu) * ia + 0x00800080u;
    ag = (ag + ((ag >> 8) & 0x00ff00ffu)) & 0xff00ff00u;
    return s + (rb | ag);                 /* premultiplied source over destination */
}

/* put the part of one layer that lies on output row y into the row buffer (the lower layers are already in it) */
static void row_layer(const struct ctx *c, uint32_t *row, const hwc_layer_1_t *l, int stride, int bpp, int y)
{
    const struct vd_handle *h = (const struct vd_handle *)l->handle;
    int dx = l->displayFrame.left, dy = l->displayFrame.top;
    int w = l->displayFrame.right - dx, sx = 0;
    if (y < dy || y >= l->displayFrame.bottom) return;
    if (dx < 0) { sx = -dx; w += dx; dx = 0; }
    if (dx + w > c->w) w = c->w - dx;
    if (w <= 0) return;
    uint32_t *d = row + dx;
    if (bpp == 2) { row565(d, (const uint16_t *)((const uint8_t *)(uintptr_t)h->base + ((size_t)(y - dy) * stride + sx) * 2), w); return; }
    const uint32_t *s = (const uint32_t *)((const uint8_t *)(uintptr_t)h->base + ((size_t)(y - dy) * stride + sx) * 4);
    if (l->blending == HWC_BLENDING_NONE) { memcpy(d, s, (size_t)w * 4); return; }
    for (int x = 0; x < w; x++) {
        uint32_t p = s[x];
        uint32_t a = p >> 24;
        if (a == 255) d[x] = p;
        else if (p) d[x] = blend_px(p, d[x]);
    }
}

static int covers_all(const struct ctx *c, const hwc_layer_1_t *l)
{
    return l->blending == HWC_BLENDING_NONE && l->displayFrame.left <= 0 && l->displayFrame.top <= 0 &&
           l->displayFrame.right >= c->w && l->displayFrame.bottom >= c->h;
}

static int hwc_prepare(hwc_composer_device_1_t *dev, size_t n, hwc_display_contents_1_t **disp)
{
    struct ctx *c = (struct ctx *)dev;
    if (n < 1 || !disp[0]) return 0;
    hwc_display_contents_1_t *list = disp[0];
    time_t t = time(NULL);
    if (t != c->force_checked) { c->force_checked = t; c->force_gles = access(KFB_GLES, F_OK) == 0; }
    size_t nl = list->numHwLayers ? list->numHwLayers - 1 : 0;      /* the last one is the framebuffer target */
    int ok = !c->force_gles && nl > 0 && nl <= 32 && c->fb;
    int st;
    for (size_t i = 0; ok && i < nl; i++) ok = layer_ok(c, &list->hwLayers[i], &st);
    for (size_t i = 0; i < nl; i++) {
        hwc_layer_1_t *l = &list->hwLayers[i];
        if (l->compositionType == HWC_BACKGROUND || l->compositionType == HWC_SIDEBAND) continue;
        l->compositionType = ok ? HWC_OVERLAY : HWC_FRAMEBUFFER;
    }
    if (!ok && c->ovl_since_gles && c->fb && !c->onepage) {
        /* GLES draws only what changed and takes the rest of the frame from its previous buffer: both pages must hold
           the picture that is on screen now */
        memcpy(c->fb + (size_t)(c->last_page ^ 1) * c->page_bytes, c->fb + (size_t)c->last_page * c->page_bytes, c->page_bytes);
        c->ovl_since_gles = 0;
        c->n_sync++;
    }
    c->overlay = ok;
    return 0;
}

static int hwc_set(hwc_composer_device_1_t *dev, size_t n, hwc_display_contents_1_t **disp)
{
    struct ctx *c = (struct ctx *)dev;
    if (n < 1 || !disp[0]) return 0;
    hwc_display_contents_1_t *list = disp[0];
    size_t nl = list->numHwLayers ? list->numHwLayers - 1 : 0;
    for (size_t i = 0; i < list->numHwLayers; i++) {
        hwc_layer_1_t *l = &list->hwLayers[i];
        if (l->acquireFenceFd >= 0) { close(l->acquireFenceFd); l->acquireFenceFd = -1; }
        l->releaseFenceFd = -1;
    }
    list->retireFenceFd = -1;
    if (c->overlay && nl > 0) {
        long long t0 = now_ns();
        /* in place, into the page that is on screen: only rows that differ are written, so we know what changed */
        int page = c->last_page;
        uint8_t *dst = c->fb + (size_t)page * c->page_bytes;
        size_t first = 0;
        for (size_t i = nl; i-- > 0;)
            if (covers_all(c, &list->hwLayers[i])) { first = i; break; }
        int base_full = covers_all(c, &list->hwLayers[first]);
        int st[32], bp[32];
        size_t top = nl > 32 ? 32 : nl;       /* prepare() refused more than 32 layers */
        for (size_t i = first; i < top; i++) { st[i] = 0; bp[i] = 4; if (!layer_ok2(c, &list->hwLayers[i], &st[i], &bp[i])) st[i] = 0; }
        const struct vd_handle *bh = (const struct vd_handle *)list->hwLayers[first].handle;
        int bdy = list->hwLayers[first].displayFrame.top, bdx = list->hwLayers[first].displayFrame.left;
        int y0 = -1, y1 = 0;
        const size_t rb = (size_t)c->w * 4;
        for (int y = 0; y < c->h; y++) {
            const uint8_t *src;
            int single = base_full && st[first] && bp[first] == 4;
            for (size_t i = first + 1; single && i < top; i++)
                if (st[i] && y >= list->hwLayers[i].displayFrame.top && y < list->hwLayers[i].displayFrame.bottom) single = 0;
            if (single) {      /* the usual row: one opaque full-width layer, straight from its buffer */
                src = (const uint8_t *)(uintptr_t)bh->base + ((size_t)(y - bdy) * st[first] + (size_t)(-bdx)) * 4;
            } else {
                memset(c->rowbuf, 0, rb);
                for (size_t i = first; i < top; i++)
                    if (st[i]) row_layer(c, c->rowbuf, &list->hwLayers[i], st[i], bp[i], y);
                src = (const uint8_t *)c->rowbuf;
            }
            uint8_t *d = dst + (size_t)y * rb;
            if (memcmp(d, src, rb)) {
                memcpy(d, src, rb);
                if (y0 < 0) y0 = y;
                y1 = y + 1;
            }
        }
        if (y0 >= 0) { notify(c, page, y0, y1); c->ovl_since_gles = 1; c->n_ovl++; }
        else c->n_same++;
        c->last_us = (long)((now_ns() - t0) / 1000);
        if (c->last_us > c->max_us) c->max_us = c->last_us;
    } else if (list->numHwLayers) {
        const hwc_layer_1_t *t = &list->hwLayers[list->numHwLayers - 1];
        const struct vd_handle *h = (const struct vd_handle *)t->handle;
        if (t->compositionType == HWC_FRAMEBUFFER_TARGET && h && h->magic == VD_MAGIC && (h->flags & VD_FLAG_FB)) {
            notify(c, (int)((size_t)h->offset / c->page_bytes) & 1, 0, 0);
            c->n_gles++;
        }
    }
    return 0;
}

static void *vsync_thread(void *arg)
{
    struct ctx *c = arg;
    long long next = now_ns();
    for (;;) {
        pthread_mutex_lock(&c->lock);
        while (!c->vsync_on) { pthread_cond_wait(&c->cond, &c->lock); next = now_ns(); }
        pthread_mutex_unlock(&c->lock);
        next += c->period_ns;
        long long t = now_ns();
        if (next < t) next = t + c->period_ns - (t - next) % c->period_ns;
        struct timespec ts = { next / 1000000000LL, next % 1000000000LL };
        while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR) {}
        if (c->vsync_on && c->procs && c->procs->vsync) c->procs->vsync(c->procs, HWC_DISPLAY_PRIMARY, next);
    }
    return NULL;
}

static int hwc_event_control(hwc_composer_device_1_t *dev, int disp, int event, int enabled)
{
    struct ctx *c = (struct ctx *)dev;
    if (disp != HWC_DISPLAY_PRIMARY || event != HWC_EVENT_VSYNC) return -EINVAL;
    pthread_mutex_lock(&c->lock);
    c->vsync_on = enabled != 0;
    pthread_cond_signal(&c->cond);
    pthread_mutex_unlock(&c->lock);
    return 0;
}

static int hwc_blank(hwc_composer_device_1_t *dev, int disp, int blank) { (void)dev; (void)disp; (void)blank; return 0; }

static int hwc_query(hwc_composer_device_1_t *dev, int what, int *value)
{
    struct ctx *c = (struct ctx *)dev;
    switch (what) {
    case HWC_BACKGROUND_LAYER_SUPPORTED: *value = 0; return 0;
    case HWC_VSYNC_PERIOD: *value = (int)c->period_ns; return 0;
    case HWC_DISPLAY_TYPES_SUPPORTED: *value = HWC_DISPLAY_PRIMARY_BIT; return 0;
    default: return -EINVAL;
    }
}

static void hwc_register_procs(hwc_composer_device_1_t *dev, hwc_procs_t const *procs) { ((struct ctx *)dev)->procs = procs; }

static void hwc_dump(hwc_composer_device_1_t *dev, char *buf, int len)
{
    struct ctx *c = (struct ctx *)dev;
    snprintf(buf, len, "hwc_kindle: %dx%d %ld Hz, frames written here %lu + unchanged %lu (last %ld us, max %ld us), GLES frames %lu, page syncs %lu, force_gles=%d onepage=%d\n",
             c->w, c->h, 1000000000L / c->period_ns, c->n_ovl, c->n_same, c->last_us, c->max_us, c->n_gles, c->n_sync, c->force_gles, c->onepage);
}

static int hwc_get_configs(hwc_composer_device_1_t *dev, int disp, uint32_t *configs, size_t *num)
{
    (void)dev;
    if (disp != HWC_DISPLAY_PRIMARY) return -EINVAL;
    if (*num < 1) return 0;
    configs[0] = 0;
    *num = 1;
    return 0;
}

static int hwc_get_attributes(hwc_composer_device_1_t *dev, int disp, uint32_t config, const uint32_t *attr, int32_t *values)
{
    struct ctx *c = (struct ctx *)dev;
    (void)config;
    if (disp != HWC_DISPLAY_PRIMARY) return -EINVAL;
    for (int i = 0; attr[i] != HWC_DISPLAY_NO_ATTRIBUTE; i++) {
        switch (attr[i]) {
        case HWC_DISPLAY_VSYNC_PERIOD: values[i] = (int32_t)c->period_ns; break;
        case HWC_DISPLAY_WIDTH: values[i] = c->w; break;
        case HWC_DISPLAY_HEIGHT: values[i] = c->h; break;
        case HWC_DISPLAY_DPI_X: values[i] = 300 * 1000; break;
        case HWC_DISPLAY_DPI_Y: values[i] = 300 * 1000; break;
        default: return -EINVAL;     /* SurfaceFlinger asks again without the attributes we do not know */
        }
    }
    return 0;
}

static int hwc_close(hw_device_t *dev) { (void)dev; return 0; }      /* SurfaceFlinger never closes it while it runs */

static int hwc_open(const struct hw_module_t *module, const char *name, struct hw_device_t **device)
{
    if (strcmp(name, HWC_HARDWARE_COMPOSER)) return -EINVAL;
    if (access(KFB_FILE, R_OK | W_OK) != 0 || access(KFB_OFF, F_OK) == 0) {
        ALOGI("not used (%s)", access(KFB_OFF, F_OK) == 0 ? "switched off" : "no virtual framebuffer");
        return -ENODEV;
    }
    struct ctx *c = calloc(1, sizeof(*c));
    if (!c) return -ENOMEM;
    c->w = 1272; c->h = 1696;
    FILE *f = fopen(KFB_INFO, "r");
    if (f) { if (fscanf(f, "%d %d", &c->w, &c->h) != 2) { c->w = 1272; c->h = 1696; } fclose(f); }
    int hz = 30;
    f = fopen(KFB_HZ, "r");
    if (f) { if (fscanf(f, "%d", &hz) != 1) hz = 30; fclose(f); }
    if (hz < 10 || hz > 60) hz = 30;
    c->period_ns = 1000000000L / hz;
    c->page_bytes = (size_t)c->w * c->h * 4;
    int fd = open(KFB_FILE, O_RDWR | O_CLOEXEC);
    if (fd < 0) { free(c); return -errno; }
    struct stat sb;
    if (fstat(fd, &sb) < 0 || (size_t)sb.st_size < c->page_bytes * 2) { close(fd); free(c); return -ENODEV; }
    c->fb = mmap(NULL, c->page_bytes * 2, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (c->fb == MAP_FAILED) { free(c); return -ENOMEM; }
    c->fifo = -1;
    c->page_noted = -1;
    c->onepage = access(KFB_ONEPAGE, F_OK) == 0;
    c->rowbuf = malloc((size_t)c->w * 4);
    if (!c->rowbuf) { free(c); return -ENOMEM; }
    pthread_mutex_init(&c->lock, NULL);
    pthread_cond_init(&c->cond, NULL);
    c->dev.common.tag = HARDWARE_DEVICE_TAG;
    c->dev.common.version = HWC_DEVICE_API_VERSION_1_1;
    c->dev.common.module = (struct hw_module_t *)module;
    c->dev.common.close = hwc_close;
    c->dev.prepare = hwc_prepare;
    c->dev.set = hwc_set;
    c->dev.eventControl = hwc_event_control;
    c->dev.blank = hwc_blank;
    c->dev.query = hwc_query;
    c->dev.registerProcs = hwc_register_procs;
    c->dev.dump = hwc_dump;
    c->dev.getDisplayConfigs = hwc_get_configs;
    c->dev.getDisplayAttributes = hwc_get_attributes;
    pthread_create(&c->vthread, NULL, vsync_thread, c);
    ALOGI("virtual e-ink composer: %dx%d, %d Hz%s", c->w, c->h, hz, c->onepage ? ", one page" : "");
    *device = &c->dev.common;
    return 0;
}

static struct hw_module_methods_t hwc_methods = { .open = hwc_open };

hwc_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = HWC_MODULE_API_VERSION_0_1,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = HWC_HARDWARE_MODULE_ID,
        .name = "VeraDroid e-ink composer",
        .author = "VeraDroid",
        .methods = &hwc_methods,
    }
};
