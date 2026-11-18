/* tests/hwc-test.sh driver: hwcomposer.kindle (android/hwcomposer/hwc_kindle.c, built into this file for the host with
 * KFB_DIR = a temp directory) fed with SurfaceFlinger-like frames; checks which page each frame lands on and what the
 * bridge is told on epd.fifo.
 *   run <dir> ok     the bridge created fb2.ok: a dialog frame goes to page 2, the frame after it back to page 0 / 1
 *   run <dir> nofb2  no fb2.ok (a bridge that does not know page 2): dialog frames are GLES frames, "P 2" never sent */
#include "hwc_kindle.c"
#include <assert.h>

#define TW 64
#define TH 48
static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static struct vd_handle app_h, dlg_h, fbt_h;
static uint32_t *app_px, *dlg_px;
static int rfd;

static void mkbuf(struct vd_handle *h, uint32_t **px, int w, int hh, uint32_t colour)
{
    size_t sz = page_round((size_t)((hh + 1) & ~1) * ((w + 1) & ~1) * 4 + 4);
    *px = calloc(1, sz);
    for (int i = 0; i < ((w + 1) & ~1) * hh; i++) (*px)[i] = colour;
    memset(h, 0, sizeof(*h));
    h->nh.numFds = 1; h->magic = VD_MAGIC; h->size = (int)sz; h->base = (uint64_t)(uintptr_t)*px;
}

static void layer(hwc_layer_1_t *l, const struct vd_handle *h, int x, int y, int w, int hh, int blend)
{
    memset(l, 0, sizeof(*l));
    l->compositionType = HWC_FRAMEBUFFER; l->handle = (buffer_handle_t)h; l->blending = blend; l->planeAlpha = 255;
    l->sourceCropi = (hwc_rect_t){0, 0, w, hh}; l->displayFrame = (hwc_rect_t){x, y, x + w, y + hh};
    l->acquireFenceFd = l->releaseFenceFd = -1;
}

/* one frame: app, [dim, dialog], framebuffer target on page fbpage; returns what the bridge was told */
static char said[256];
static const char *frame(hwc_composer_device_1_t *dev, int dialog, int fbpage, int *overlay)
{
    static union { hwc_display_contents_1_t d; char b[sizeof(hwc_display_contents_1_t) + 5 * sizeof(hwc_layer_1_t)]; } u;
    hwc_display_contents_1_t *list = &u.d;
    memset(&u, 0, sizeof(u));
    size_t n = 0;
    layer(&list->hwLayers[n++], &app_h, 0, 0, TW, TH, HWC_BLENDING_NONE);
    if (dialog) {
        hwc_layer_1_t *d = &list->hwLayers[n++];
        memset(d, 0, sizeof(*d));
        d->compositionType = HWC_FRAMEBUFFER; d->flags = HWC_SKIP_LAYER; d->blending = HWC_BLENDING_PREMULT; d->planeAlpha = 255;
        d->displayFrame = (hwc_rect_t){-TW / 2, -TH / 2, TW + TW / 2, TH + TH / 2};    /* WindowManager's 1.5x quad */
        d->acquireFenceFd = d->releaseFenceFd = -1;
        layer(&list->hwLayers[n++], &dlg_h, 8, 8, TW - 16, TH - 16, HWC_BLENDING_PREMULT);
    }
    hwc_layer_1_t *t = &list->hwLayers[n++];
    memset(t, 0, sizeof(*t));
    fbt_h.offset = fbpage * TW * TH * 4;
    t->compositionType = HWC_FRAMEBUFFER_TARGET; t->handle = (buffer_handle_t)&fbt_h; t->blending = HWC_BLENDING_PREMULT;
    t->acquireFenceFd = t->releaseFenceFd = -1;
    list->numHwLayers = n;
    hwc_display_contents_1_t *disp[1] = { list };
    dev->prepare(dev, 1, disp);
    *overlay = list->hwLayers[0].compositionType == HWC_OVERLAY;
    dev->set(dev, 1, disp);
    ssize_t r = read(rfd, said, sizeof(said) - 1);
    said[r > 0 ? r : 0] = 0;
    char *nl = strchr(said, '\n'); if (nl) *nl = 0;
    return said;
}

int main(int argc, char **argv)
{
    const char *dir = argv[1]; int ok = !strcmp(argv[2], "ok");
    char p[600];
    snprintf(p, sizeof(p), "%s/fifo-check", dir);       /* KFB_DIR is compiled in: make sure it is this dir */
    assert(!strncmp(KFB_DIR, dir, strlen(dir)));
    rfd = open(KFB_FIFO, O_RDONLY | O_NONBLOCK);
    assert(rfd >= 0);
    mkbuf(&app_h, &app_px, TW, TH, 0xff102030u);
    mkbuf(&dlg_h, &dlg_px, TW - 16, TH - 16, 0xffe0e0e0u);
    memset(&fbt_h, 0, sizeof(fbt_h)); fbt_h.nh.numFds = 1; fbt_h.magic = VD_MAGIC; fbt_h.flags = VD_FLAG_FB;
    hw_device_t *hd = NULL;
    int rc = HAL_MODULE_INFO_SYM.common.methods->open(&HAL_MODULE_INFO_SYM.common, HWC_HARDWARE_COMPOSER, &hd);
    CHECK(rc == 0 && hd, "open: %d", rc);
    if (!hd) return 1;
    hwc_composer_device_1_t *dev = (hwc_composer_device_1_t *)hd;
    struct ctx *c = (struct ctx *)dev;
    int ovl;
    const char *s = frame(dev, 0, 0, &ovl);
    CHECK(ovl && !strncmp(s, "P 0", 3), "app frame: overlay %d, said '%s'", ovl, s);
    CHECK(((uint32_t *)c->fb)[0] == 0xff102030u, "page 0 holds the app");
    for (int i = 0; i < 3; i++) {          /* the dialog fades in: a few frames */
        s = frame(dev, 1, i & 1, &ovl);
        if (ok) CHECK((ovl && s[0] == 'P' && s[2] == '2') || (ovl && !s[0]), "dialog frame %d: overlay %d, said '%s' (want P 2)", i, ovl, s);
        else CHECK(!ovl && strncmp(s, "P 2", 3), "dialog frame %d without fb2.ok: overlay %d, said '%s' (want GLES, never P 2)", i, ovl, s);
    }
    if (ok) {
        uint32_t mid = ((uint32_t *)c->fb2)[(TH / 2) * TW + TW / 2], edge = ((uint32_t *)c->fb2)[1];
        CHECK(mid == 0xffe0e0e0u, "page 2: dialog in the middle (%08x)", mid);
        CHECK(edge != 0xff102030u && (edge & 0xff) < 0x30, "page 2: app under the veil is darker (%08x)", edge);
    }
    /* the dialog is gone: the app changes and must reach a page the bridge reads (0 / 1 here, never 2) */
    for (int i = 0; i < TW * TH; i++) app_px[i] = 0xff405060u;
    s = frame(dev, 0, 0, &ovl);
    CHECK(ovl && s[0] == 'P' && (s[2] == '0' || s[2] == '1'), "frame after the dialog: overlay %d, said '%s' (want P 0 / P 1)", ovl, s);
    int pg = s[0] ? s[2] - '0' : 0;
    CHECK(((uint32_t *)(c->fb + (size_t)(pg & 1) * c->page_bytes))[5] == 0xff405060u, "page %d holds the new app picture", pg);
    for (int i = 0; i < TW * TH; i++) app_px[i] = 0xff708090u;
    for (int i = 0; i < TW; i++) app_px[i] = 0xff708090u;
    s = frame(dev, 0, 0, &ovl);
    CHECK(ovl && s[0] == 'P' && s[2] != '2', "next frame: said '%s' (want not page 2)", s);
    char d[1024]; dev->dump(dev, d, sizeof(d)); printf("%s", d);
    printf("%s: %s\n", ok ? "fb2.ok" : "no fb2.ok", fails ? "FAILED" : "ok");
    return fails != 0;
}
