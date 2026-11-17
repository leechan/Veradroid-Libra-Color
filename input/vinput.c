// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * veradroid-input: touch front end for VeraDroid.
 *
 * Grabs the Kindle touch screen (FocalTech fts_ts, multitouch type B), recognises the global gestures (they must work in
 * every Android app, and cannot be switched off for the bottom-edge "back"), and passes everything else through to a
 * uinput virtual touch screen ("veradroid-touch") that the Android container reads. Gesture results are injected as
 * key events on a second virtual device ("veradroid-keys") or run as host actions.
 *
 *   edge gestures (single finger, never forwarded):
 *       start in the bottom edge and swipe up      -> KEY_BACK
 *       start in the top edge and swipe down       -> action "panel"
 *   two fingers (second finger within --window ms of the first; never forwarded):
 *       tap                                         -> action "clear"   (full-screen refresh)
 *       long press (>= 2 s)                         -> action "invert"
 *       horizontal swipe                            -> KEY_BACK
 *       vertical swipe, left half / right half      -> "light+/-" / "warmth+/-"
 *   one finger, long press (>= --corner-ms) in a screen corner -> actions "tl" "tr" "bl" "br" (the finger is released
 *       towards Android first)
 *
 * Each gesture can be switched off on its own (--gconf FILE, KEY=0|1 lines, re-read on the next touch after it changes):
 *   G_EDGE_BACK (bottom edge up -> back)  G_EDGE_PANEL (top edge down -> panel)  G_TWO_TAP (clear)  G_TWO_LONG (invert)
 *   G_TWO_BACK (two-finger horizontal -> back)  G_TWO_SLIDE (two-finger vertical -> light / warmth)
 *   G_CORNERS=tl,bl  -- only these corners take the long press (the ones with an action; "none" = no corner; key absent = all).
 *   G_BACK_EXCLUDE=pkg,pkg  -- no bottom-edge back while one of these apps is in front (--fg FILE holds the foreground
 *   package, written by VeraHome). WeRead uses its own swipe-up for the reader toolbar.
 *   With every two-finger gesture off, two-finger touches go to Android (pinch zoom).
 *
 * Actions run  sh <actdir>/action.sh <name> [arg]  (the host decides what they do), and are logged.
 *
 * Signals: SIGUSR1 releases the touch screen (the Kindle UI can use it; we drop everything we read), SIGUSR2 grabs it again.
 *
 * Bezel double tap (--tapdev, PW6 and other models with the lis2du12 accelerometer): the Kindle's gesturetapd turns the
 *   accelerometer's double-tap interrupt (iio lis2du12_tap_tap + 30 extra samples, its own filter) into keys on a uinput
 *   device "gesture_tap" (KEY_F6..F8 advertised). It only runs where devcap allows it ("Base config device" -> exits).
 *   We grab that device while Android is in front and turn a press into KEY_VOLUMEDOWN (next page in WeRead and most
 *   readers); G_TAP=0 in --gconf switches it off, G_TAP_KEY=pageup|pagedown|volup|voldown picks the key.
 *
 * Rotation (--rotate 0|90|180|270, docs/rotation.md): Android draws upright into a buffer of the LOGICAL size (portrait
 *   W x H for 0/180, H x W for 90/270) and veradroid-epd rotates it onto the panel. Here every position event is turned
 *   from panel coordinates into logical ones as soon as it is read (also the --inject ones, which stay in panel
 *   coordinates like a real finger), so the gesture code, edge strips, corners and the virtual touch screen all work in
 *   the logical picture. --w/--h stay the PANEL size in pixels (--vw: visible width when --w is the framebuffer stride,
 *   PW5 1248/1236); the flips use them (not the touch range) so that touch and picture use exactly the same mapping as
 *   veradroid-epd. Logical size: W x H at 0/180, H x VW at 90/270. 90 = the content is turned 90 degrees clockwise on the panel (its top is
 *   at the panel's right edge). A "ROTATE=n" line in --gconf switches live between 0/180 or 90/270 (same logical size;
 *   without --rotate the virtual touch screen keeps the source ranges, which must then equal the panel pixels).
 *   With --rotate the single-touch axes (ABS_X / ABS_Y, PW5 goodix) are rotated and passed on as well.
 *
 * Source protocols (detected from the device's ABS bits, --proto b|a|st forces one):
 *   B   (ABS_MT_SLOT: fts_ts, goodix-ts gtx8, cyttsp4, ili211x, pt_mt) -- read as is, the original path, unchanged.
 *   A   (ABS_MT_POSITION_X without ABS_MT_SLOT: contacts separated by SYN_MT_REPORT, a frame without contacts = all up)
 *       -- every frame is turned into slot events before anything else looks at it: a contact is matched to a slot by
 *       ABS_MT_TRACKING_ID when the driver sends one, otherwise to the nearest finger of the previous frame (greedy, at
 *       most a third of the screen away); a slot with no contact in a frame is released. New contacts get fresh tracking
 *       ids. A contact with ABS_MT_PRESSURE 0 or a frame with BTN_TOUCH 0 counts as lifted.
 *   ST  (ABS_X / ABS_Y + BTN_TOUCH only) -- one finger in slot 0 (down while BTN_TOUCH is 1).
 *   For A and ST the virtual touch screen is a protocol-B one (ABS_MT_SLOT + ABS_MT_TRACKING_ID, position ranges from the
 *   source), so the gestures and Android see exactly what a B panel would give. The conversion adds no delay: it works
 *   on the frame as it is read.
 *
 * Usage: veradroid-input <touch-event-dev> <log-file> <action-script> [--gconf FILE] [--fg FILE] [--w 1272] [--h 1696] [--edge 60] [--window 50]
 *                        [--corner 160] [--corner-ms 2000] [--edge-hold 60] [--edge-swipe 80] [--edge-back 0|1] [--no-gestures]
 *                        [--rotate 0|90|180|270] [--proto b|a|st]
 * Build (armhf, static): arm-linux-gnueabihf-gcc -O2 -static vinput.c -o veradroid-input
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAXSLOT 16   /* cyttsp4 (PW2/PW3/Voyage/Oasis 1) has max_tchs+1 slots, typically 11; ilitek 10; fts_ts 2 */
#define MAXEV 512

static int W = 1272, H = 1696, EDGE = 60, EDGE_TOP = -1, TOUCH_DEBUG = 0, WINDOW_MS = 80, CORNER = 160, CORNER_MS = 2000, GESTURES = 1, EDGE_BACK = 1;
static const char *LOGF = "/dev/null", *ACT = "", *FLAGF = NULL, *INJECT = NULL, *GCONF = NULL, *FGF = NULL;
/* per-gesture switches (--gconf) */
static int G_EDGE_BACK = 1, G_EDGE_PANEL = 1, G_TWO_TAP = 1, G_TWO_LONG = 1, G_TWO_BACK = 1, G_TWO_SLIDE = 1;
static int G_TAP = 1, G_TAP_KEY = KEY_VOLUMEDOWN;   /* bezel double tap (gesture_tap) -> this key, see the header */
static int tapfd = -1;
static const char *TAPDEV = NULL;
static int G_EDGE_SENS = 1;            /* edge swipe sensitivity: 0 low, 1 standard, 2 high (scales the strip width and the swipe distance) */
static int EDGE_SWIPE;                 /* defined with its default further down */
static int EDGE_BASE = -1, EDGE_TOP_BASE = -1, EDGE_SWIPE_BASE = -1;   /* command-line values, captured at startup */
static char G_BACK_EXCLUDE[512] = "";
static char G_CORNERS[24] = "all";   /* corners whose long press is a gesture ("tl,bl", "" = none, "all"); others stay Android's */
/* rotation (see the header): ROT_ON = --rotate was given at all; PW/PH = panel size in pixels; W/H become the logical size */
static int ROT = 0, ROT_ON = 0, PW = 0, PH = 0, VW = 0;   /* FLAGF exists -> gestures are off (only bottom-edge back stays) */
static volatile sig_atomic_t quit = 0, want_release = 0, want_grab = 0;
static int paused = 0;
static int btn_down = 0;
static int src_btn_touch = 0;
static int tfd = -1, ufd = -1, kfd = -1;
enum { PROTO_B, PROTO_A, PROTO_ST };
static int src_proto = PROTO_B, proto_forced = -1;

static void on_sig(int s) { (void)s; quit = 1; }
static void on_usr1(int s) { (void)s; want_release = 1; }   /* give the touch screen back to the Kindle */
static void on_usr2(int s) { (void)s; want_grab = 1; }      /* take it again */
static long now_ms(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L; }

static void logf_(const char *fmt, ...)
{
    FILE *f = fopen(LOGF, "a");
    if (!f) return;
    va_list ap; va_start(ap, fmt);
    fprintf(f, "[%ld] ", now_ms());
    vfprintf(f, fmt, ap);
    fputc('\n', f);
    va_end(ap); fclose(f);
}

static long long gconf_sig = -2;   /* long long: on 32-bit ARM tv_sec*1000 overflowed long -> looked like a stat failure -> file never parsed */
static void gconf_load(void)
{
    if (!GCONF) return;
    struct stat st;
    int ok = stat(GCONF, &st) == 0;
    long long sig = !ok ? -1 : (long long)st.st_mtim.tv_sec * 1000 + st.st_mtim.tv_nsec / 1000000 + (long long)st.st_size * 7919;
    if (sig == gconf_sig) return;
    gconf_sig = sig;
    G_EDGE_BACK = G_EDGE_PANEL = G_TWO_TAP = G_TWO_LONG = G_TWO_BACK = G_TWO_SLIDE = 1; G_BACK_EXCLUDE[0] = 0; G_EDGE_SENS = 1;
    G_TAP = 1; G_TAP_KEY = KEY_VOLUMEDOWN; snprintf(G_CORNERS, sizeof(G_CORNERS), "all");
    FILE *f = !ok ? NULL : fopen(GCONF, "r");
    if (f) {
        char line[600];
        while (fgets(line, sizeof(line), f)) {
            char *eq = strchr(line, '='); if (!eq) continue;
            *eq = 0; char *v = eq + 1; v[strcspn(v, "\r\n")] = 0;
            int b = atoi(v) != 0;
            if (!strcmp(line, "G_EDGE_BACK")) G_EDGE_BACK = b;
            else if (!strcmp(line, "G_EDGE_PANEL")) G_EDGE_PANEL = b;
            else if (!strcmp(line, "G_TWO_TAP")) G_TWO_TAP = b;
            else if (!strcmp(line, "G_TWO_LONG")) G_TWO_LONG = b;
            else if (!strcmp(line, "G_TWO_BACK")) G_TWO_BACK = b;
            else if (!strcmp(line, "G_TWO_SLIDE")) G_TWO_SLIDE = b;
            else if (!strcmp(line, "G_TAP")) G_TAP = b;
            else if (!strcmp(line, "G_TAP_KEY")) {
                if (!strcmp(v, "pageup")) G_TAP_KEY = KEY_PAGEUP;
                else if (!strcmp(v, "pagedown")) G_TAP_KEY = KEY_PAGEDOWN;
                else if (!strcmp(v, "volup")) G_TAP_KEY = KEY_VOLUMEUP;
                else G_TAP_KEY = KEY_VOLUMEDOWN;
            }
            else if (!strcmp(line, "G_EDGE_SENS")) { G_EDGE_SENS = atoi(v); if (G_EDGE_SENS < 0 || G_EDGE_SENS > 2) G_EDGE_SENS = 1; }
            else if (!strcmp(line, "G_CORNERS")) snprintf(G_CORNERS, sizeof(G_CORNERS), "%s", strcmp(v, "none") ? v : "");
            else if (!strcmp(line, "G_BACK_EXCLUDE")) { snprintf(G_BACK_EXCLUDE, sizeof(G_BACK_EXCLUDE), "%s", strcmp(v, "none") ? v : ""); }
            else if (!strcmp(line, "ROTATE")) {
                /* live only within the same logical size: the virtual touch screen's ranges are fixed at start */
                int r = atoi(v);
                if ((r == 0 || r == 90 || r == 180 || r == 270) && (r % 180) == (ROT % 180) && r != ROT) {
                    logf_("rotate %d -> %d", ROT, r);
                    ROT = r;
                }
            }
        }
        fclose(f);
    }
    if (EDGE_BASE > 0) {   /* low: narrower strip, longer swipe; high: wider strip, shorter swipe */
        static const int strip_pct[3] = { 67, 100, 140 }, swipe_pct[3] = { 150, 100, 60 };
        EDGE = EDGE_BASE * strip_pct[G_EDGE_SENS] / 100;
        EDGE_TOP = EDGE_TOP_BASE * strip_pct[G_EDGE_SENS] / 100;
        EDGE_SWIPE = EDGE_SWIPE_BASE * swipe_pct[G_EDGE_SENS] / 100;
    }
    logf_("gconf: edge_sens=%d (strip %d/%d px, swipe %d px)", G_EDGE_SENS, EDGE, EDGE_TOP, EDGE_SWIPE);
    logf_("gconf: edge_back=%d edge_panel=%d two_tap=%d two_long=%d two_back=%d two_slide=%d exclude=%s",
          G_EDGE_BACK, G_EDGE_PANEL, G_TWO_TAP, G_TWO_LONG, G_TWO_BACK, G_TWO_SLIDE, G_BACK_EXCLUDE[0] ? G_BACK_EXCLUDE : "-");
}
/* is the foreground app (VeraHome writes it to --fg) in G_BACK_EXCLUDE? */
static int back_excluded(void)
{
    if (!FGF || !G_BACK_EXCLUDE[0]) return 0;
    char pkg[256] = "";
    FILE *f = fopen(FGF, "r");
    if (!f) return 0;
    if (!fgets(pkg, sizeof(pkg), f)) pkg[0] = 0;
    fclose(f);
    pkg[strcspn(pkg, "\r\n /")] = 0;
    if (!pkg[0]) return 0;
    size_t l = strlen(pkg);
    for (const char *p = G_BACK_EXCLUDE; (p = strstr(p, pkg)) != NULL; p += l) {
        int start_ok = p == G_BACK_EXCLUDE || p[-1] == ',';
        int end_ok = p[l] == 0 || p[l] == ',';
        if (start_ok && end_ok) return 1;
    }
    return 0;
}
static int two_any(void) { return G_TWO_TAP || G_TWO_LONG || G_TWO_BACK || G_TWO_SLIDE; }

/* ---- what Android has been told (every write to the virtual touch screen goes through uout) ----
   BTN_TOUCH on the virtual device follows the fingers we forwarded, not the panel's own BTN_TOUCH: Android's multitouch
   reader treats a contact while BTN_TOUCH is 0 as hovering (ACTION_HOVER_*, no tap). The PW5 goodix driver releases every
   finger when the Kindle locks the panel for the screensaver; when a finger was down at that moment (tapping "sleep" on
   the home screen, a thumb resting on the glass) its first contact after the wake comes without BTN_TOUCH 1 (pw5-5192
   emulator, real goodix driver), so the first tap after waking reached Android as a hover and did nothing. */
static int out_slot = 0, out_btn = 0;
static unsigned char out_act[MAXSLOT];
static unsigned long btn_fixes = 0;
static void uraw(int type, int code, int value)
{
    struct input_event e;
    memset(&e, 0, sizeof(e));
    e.type = type; e.code = code; e.value = value;
    if (write(ufd, &e, sizeof(e)) < 0) { /* device gone */ }
}
static void uout(const struct input_event *e)
{
    if (e->type == EV_ABS && e->code == ABS_MT_SLOT) out_slot = e->value;
    else if (e->type == EV_ABS && e->code == ABS_MT_TRACKING_ID) { if (out_slot >= 0 && out_slot < MAXSLOT) out_act[out_slot] = e->value >= 0; }
    else if (e->type == EV_KEY && e->code == BTN_TOUCH) out_btn = e->value != 0;
    else if (e->type == EV_SYN && e->code == SYN_REPORT) {
        int any = 0;
        for (int i = 0; i < MAXSLOT; i++) any |= out_act[i];
        if (any != out_btn) {
            uraw(EV_KEY, BTN_TOUCH, any); out_btn = any;
            if (++btn_fixes <= 20) logf_("btn_touch: panel %s, sent BTN_TOUCH %d with the frame", any ? "left it out on a new contact" : "kept it down with no contact", any);
        }
    }
    if (write(ufd, e, sizeof(*e)) < 0) { /* device gone */ }
}
static void emit(int fd, int type, int code, int value)
{
    struct input_event e;
    memset(&e, 0, sizeof(e));
    e.type = type; e.code = code; e.value = value;
    if (fd == ufd) { uout(&e); return; }
    if (write(fd, &e, sizeof(e)) < 0) { /* device gone */ }
}

static void key_tap(int code)
{
    emit(kfd, EV_KEY, code, 1); emit(kfd, EV_SYN, SYN_REPORT, 0);
    emit(kfd, EV_KEY, code, 0); emit(kfd, EV_SYN, SYN_REPORT, 0);
}

static void action(const char *name, const char *arg)
{
    logf_("action %s %s", name, arg ? arg : "");
    if (!ACT[0]) return;
    pid_t p = fork();
    if (p == 0) {
        setsid();
        execlp("sh", "sh", ACT, name, arg ? arg : "", (char *)NULL);
        _exit(127);
    }
    /* children are reaped by SIGCHLD ignore */
}

/* back gesture: the key for Android, and "hint back" so the host shows its on-screen badge (action.sh, GESTURE_HINT) */
static void back_key(void)
{
    key_tap(KEY_BACK);
    action("hint", "back");
}

/* ---- touch state ---- */
struct slot { int active; int x, y; int sx, sy; long t0, tl; };   /* tl: last event for this slot */
static struct slot sl[MAXSLOT];
static int cur_slot = 0, slot_ign = 0;   /* slot_ign: the driver is talking about a slot >= MAXSLOT */

static int count_active(void) { int n = 0; for (int i = 0; i < MAXSLOT; i++) n += sl[i].active; return n; }

/* ---- resync with the kernel after lost events ----
   The evdev buffer of a 3.0 kernel holds 64 events (a few frames of a multitouch panel). When the reader is starved
   (single-core A9, an app starting / GC / dexopt), the kernel throws the oldest events away and sends SYN_DROPPED. A lost
   ABS_MT_TRACKING_ID -1 left a slot "active" here for good: every later tap then looked like a second finger (TWO: never
   forwarded), so Android saw no touches while the host gestures still worked (Voyage report, 2026-11-16).
   Fix: after SYN_DROPPED, and whenever a new finger lands while another one is believed down, ask the kernel which slots
   really hold a finger (EVIOCGMTSLOTS) and lift the ones it does not know, here and in Android. */
#ifndef EVIOCGMTSLOTS
#define EVIOCGMTSLOTS(len) _IOC(_IOC_READ, 'E', 0x0a, len)
#endif
static unsigned long resync_lifts = 0, drops = 0;
#define STALE_MS 3000
static void handle_frame(struct input_event *fr, int n);
static void resync_slots(int after_drop)
{
    if (src_proto != PROTO_B || tfd < 0) return;
    struct { uint32_t code; int32_t v[MAXSLOT]; } q;
    memset(&q, 0, sizeof(q));
    q.code = ABS_MT_TRACKING_ID;
    if (ioctl(tfd, EVIOCGMTSLOTS(sizeof(q)), &q) < 0) {
        /* no kernel slot state (a driver without input_mt_init_slots): after lost events lift every finger -- a finger
           that is really still down only loses the rest of this touch; while a new finger lands, lift the fingers that
           sent nothing for STALE_MS (a resting finger on these panels still reports small changes) */
        static int warned = 0;
        if (!warned) { warned = 1; logf_("resync: EVIOCGMTSLOTS failed (%s), using the fallback", strerror(errno)); }
        long now = now_ms();
        for (int i = 0; i < MAXSLOT; i++) q.v[i] = (sl[i].active && !after_drop && now - sl[i].tl < STALE_MS) ? 1 : -1;
    }
    if (after_drop) {                       /* the slot the driver's next events refer to (it only sends ABS_MT_SLOT on change) */
        struct input_absinfo ai;
        if (ioctl(tfd, EVIOCGABS(ABS_MT_SLOT), &ai) == 0 && ai.value >= 0 && ai.value < MAXSLOT) cur_slot = ai.value;
    }
    struct input_event fr[2 * MAXSLOT + 4];
    int n = 0, lifted = 0, keep = cur_slot, left = 0;
    memset(fr, 0, sizeof(fr));
#define RS(t, c, v) do { fr[n].type = (t); fr[n].code = (c); fr[n].value = (v); n++; } while (0)
    for (int i = 0; i < MAXSLOT; i++) {
        if (sl[i].active && q.v[i] < 0) { RS(EV_ABS, ABS_MT_SLOT, i); RS(EV_ABS, ABS_MT_TRACKING_ID, -1); lifted++; }
        else if (sl[i].active) left++;
    }
    if (!lifted) return;
    RS(EV_ABS, ABS_MT_SLOT, keep);          /* Android's slot pointer must be where the driver's next events expect it */
    if (src_btn_touch && !left) RS(EV_KEY, BTN_TOUCH, 0);
    RS(EV_SYN, SYN_REPORT, 0);
#undef RS
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    for (int i = 0; i < n; i++) { fr[i].time.tv_sec = ts.tv_sec; fr[i].time.tv_usec = ts.tv_nsec / 1000; }
    resync_lifts += lifted;
    logf_("resync (%s): %d stuck finger(s) lifted, %d still down", after_drop ? "events dropped" : "new touch", lifted, left);
    handle_frame(fr, n);
    cur_slot = keep;
}
/* does this frame put a finger down while we already think one is down? */
static int new_touch_over_active(const struct input_event *fr, int n)
{
    if (!count_active()) return 0;
    for (int i = 0; i < n; i++) if (fr[i].type == EV_ABS && fr[i].code == ABS_MT_TRACKING_ID && fr[i].value >= 0) return 1;
    return 0;
}

enum mode { IDLE, PENDING, PASS, EDGE_B, EDGE_T, TWO, SWALLOW, EDGE_FWD };
static enum mode md = IDLE;
static enum mode edge_kind = IDLE;     /* which edge strip (EDGE_B / EDGE_T) an EDGE_FWD touch started in */
static int EDGE_HOLD_MS = 60;          /* how long a touch in the edge strip is held before Android gets it (a back swipe fits inside) */
static int EDGE_SWIPE = 80;            /* vertical distance that turns an edge touch into back / panel */
static struct input_event held[MAXEV];
static int nheld = 0;
static long t_down = 0;
static int two_sx[2], two_sy[2], two_done = 0;
static int two_i[2] = { 0, 1 };        /* the slots of the two fingers: the first two active ones. fts_ts (PW6) has 2 slots,
                                          but cyttsp4 / ilitek / zforce have up to 10, and after a finger lifts the next one
                                          can land in any free slot, not only 0 and 1 */
static void two_begin(void)
{
    int n = 0;
    for (int i = 0; i < MAXSLOT && n < 2; i++) if (sl[i].active) two_i[n++] = i;
    if (n < 2) { two_i[0] = 0; two_i[1] = 1; }
    for (int k = 0; k < 2; k++) {
        struct slot *s = &sl[two_i[k]];
        two_sx[k] = s->sx >= 0 ? s->sx : s->x; two_sy[k] = s->sy >= 0 ? s->sy : s->y;
    }
}
static long two_t0 = 0;
static int corner_fired = 0;

static unsigned long fwd_count = 0;
static void forward(const struct input_event *e)
{
    fwd_count++;
    uout(e);
}
static void flush_held(void)
{
    if (!nheld) return;
    if (TOUCH_DEBUG) logf_("flush %d after %ldms", nheld, now_ms() - t_down);
    for (int i = 0; i < nheld; i++) forward(&held[i]);
    nheld = 0;
}
/* 给显示桥一个方向提示（下一次大面积变化用哪边滑入），不强制动画 */
static void epd_dir(int dir)
{
    int fd = open("/dev/shm/veradroid/kfb/epd.fifo", O_WRONLY | O_NONBLOCK);
    if (fd < 0) return;
    char b[32];
    int n = snprintf(b, sizeof(b), "DIR %d\n", dir);
    if (write(fd, b, n) < 0) { /* bridge not running */ }
    close(fd);
}
/* tell Android every finger is up (used when a gesture takes over after events were already forwarded) */
static void cancel_to_android(void)
{
    for (int i = 0; i < MAXSLOT; i++)
        if (sl[i].active) {
            emit(ufd, EV_ABS, ABS_MT_SLOT, i);
            emit(ufd, EV_ABS, ABS_MT_TRACKING_ID, -1);
        }
    emit(ufd, EV_KEY, BTN_TOUCH, 0);
    emit(ufd, EV_SYN, SYN_REPORT, 0);
}

static int in_corner(int x, int y, const char **name)
{
    int l = x < CORNER, r = x > W - CORNER, t = y < CORNER, b = y > H - CORNER;
    if (t && l) *name = "tl";
    if (t && r) *name = "tr";
    if (b && l) *name = "bl";
    if (b && r) *name = "br";
    if (!(t || b) || !(l || r)) return 0;
    /* only corners that have an action (G_CORNERS from --gconf): a long press in any other corner stays Android's */
    return !strcmp(G_CORNERS, "all") || strstr(G_CORNERS, *name) != NULL;
}

static void two_finger_end(void)
{
    /* classify by the movement of the first two fingers */
    long dur = now_ms() - two_t0;
    int mv[2][2];
    int n = 0;
    for (int i = 0; i < MAXSLOT && n < 2; i++) {
        (void)i;
    }
    (void)mv;
    int dx = sl[two_i[0]].x - two_sx[0], dy = sl[two_i[0]].y - two_sy[0];
    /* use the finger that moved most */
    int dx1 = sl[two_i[1]].x - two_sx[1], dy1 = sl[two_i[1]].y - two_sy[1];
    if (abs(dx1) + abs(dy1) > abs(dx) + abs(dy)) { dx = dx1; dy = dy1; }
    int mid = (two_sx[0] + two_sx[1]) / 2;
    if (two_done) return;
    if (abs(dx) < 60 && abs(dy) < 60) {
        if (dur >= 2000) { if (G_TWO_LONG) action("invert", NULL); }
        else if (dur < 500) { if (G_TWO_TAP) action("clear", NULL); }
    } else if (abs(dx) > abs(dy) * 2 && abs(dx) > 200) {
        if (!G_TWO_BACK) { two_done = 1; return; }
        logf_("two-finger horizontal swipe -> back");
        back_key();
    } else if (abs(dy) > abs(dx) * 2 && abs(dy) > 120 && G_TWO_SLIDE) {
        const char *what = mid < W / 2 ? "light" : "warmth";
        action(what, dy < 0 ? "+" : "-");
    }
    two_done = 1;
}

/* panel coordinates -> logical ones. A rotation by a multiple of 90 degrees maps each panel axis onto one logical axis,
   possibly flipped, so every event is rewritten on its own (code and value), no state is needed. */
static void rot_event(struct input_event *e)
{
    if (!ROT || e->type != EV_ABS) return;
    int isx = e->code == ABS_MT_POSITION_X || e->code == ABS_X;
    int isy = e->code == ABS_MT_POSITION_Y || e->code == ABS_Y;
    if (!isx && !isy) return;
    int mt = e->code == ABS_MT_POSITION_X || e->code == ABS_MT_POSITION_Y;
    int cx = mt ? ABS_MT_POSITION_X : ABS_X, cy = mt ? ABS_MT_POSITION_Y : ABS_Y;
    int v = e->value;
    switch (ROT) {
    case 90:  if (isx) { e->code = cy; e->value = VW - 1 - v; } else { e->code = cx; e->value = v; } break;
    case 180: if (isx) e->value = VW - 1 - v; else e->value = PH - 1 - v; break;
    case 270: if (isx) { e->code = cy; e->value = v; } else { e->code = cx; e->value = PH - 1 - v; } break;
    }
    /* the drivers report one past the last pixel (fts_ts / ili211x: 0..1272 on a 1272 panel, display-coords in the dts),
       which turned into -1 here; keep every value inside the logical picture */
    int lim = (e->code == ABS_MT_POSITION_X || e->code == ABS_X) ? W - 1 : H - 1;
    if (e->value < 0) e->value = 0;
    else if (e->value > lim) e->value = lim;
}
/* source ranges of the position axes: drivers report one past the advertised maximum at an edge (fts_ts / ili211x take
   the panel size as the maximum; cyttsp4 mirrors an axis as max - v, giving 1..max+1 on PW3 / Oasis 1), and Android 7
   drops a touch-down outside the range. Unrotated events are clamped to the source range, rotated ones in rot_event. */
static int sx_min = 0, sx_max = -1, sy_min = 0, sy_max = -1;
static void clamp_event(struct input_event *e)
{
    if (e->type != EV_ABS) return;
    if ((e->code == ABS_MT_POSITION_X || e->code == ABS_X) && sx_max > sx_min) {
        if (e->value < sx_min) e->value = sx_min; else if (e->value > sx_max) e->value = sx_max;
    } else if ((e->code == ABS_MT_POSITION_Y || e->code == ABS_Y) && sy_max > sy_min) {
        if (e->value < sy_min) e->value = sy_min; else if (e->value > sy_max) e->value = sy_max;
    }
}
static void rot_frame(struct input_event *fr, int n)
{
    if (md == IDLE) gconf_load();          /* a live 0 <-> 180 switch takes effect between touches (only stats the file) */
    if (!ROT) { for (int i = 0; i < n; i++) clamp_event(&fr[i]); return; }
    for (int i = 0; i < n; i++) rot_event(&fr[i]);
}

static void handle_frame(struct input_event *fr, int n)
{
    /* update state from the frame's events */
    int down_edge = 0;
    for (int i = 0; i < n; i++) {
        struct input_event *e = &fr[i];
        if (e->type == EV_ABS) {
            if (e->code == ABS_MT_SLOT) { slot_ign = !(e->value >= 0 && e->value < MAXSLOT); if (!slot_ign) cur_slot = e->value; }
            else if (slot_ign) continue;   /* a slot we do not track: Android still gets the events, the gestures ignore it */
            else if ((sl[cur_slot].tl = now_ms()), e->code == ABS_MT_TRACKING_ID) {
                if (e->value >= 0) { sl[cur_slot].active = 1; sl[cur_slot].t0 = now_ms(); sl[cur_slot].sx = sl[cur_slot].sy = -1; }
                else sl[cur_slot].active = 0;
            } else if (e->code == ABS_MT_POSITION_X) { sl[cur_slot].x = e->value; if (sl[cur_slot].sx < 0) sl[cur_slot].sx = e->value; }
            else if (e->code == ABS_MT_POSITION_Y) { sl[cur_slot].y = e->value; if (sl[cur_slot].sy < 0) sl[cur_slot].sy = e->value; }
        }
    }
    int active = count_active();
    (void)down_edge;
    int has_btn = 0;
    for (int i = 0; i < n; i++)
        if (fr[i].type == EV_KEY && fr[i].code == BTN_TOUCH) has_btn = 1;
    /* Some 5.19.5 panels report MT positions but never send BTN_TOUCH. Only
       synthesize it when the source has no BTN_TOUCH capability; devices that
       already send it (older PW6, PW5, KOReader) must not get duplicate downs. */
    if (!src_btn_touch && !has_btn) {
        if (active && !btn_down) { emit(ufd, EV_KEY, BTN_TOUCH, 1); btn_down = 1; }
        else if (!active && btn_down) { emit(ufd, EV_KEY, BTN_TOUCH, 0); btn_down = 0; }
    }
    if (TOUCH_DEBUG) {
        static int prev_active = 0;
        if (active != prev_active) {
            logf_("touch active %d->%d slot%d x=%d y=%d start=%d,%d", prev_active, active, cur_slot, sl[cur_slot].x, sl[cur_slot].y, sl[cur_slot].sx, sl[cur_slot].sy);
            prev_active = active;
        }
    }

    int gest = GESTURES && !(FLAGF && access(FLAGF, F_OK) == 0);

    switch (md) {
    case IDLE:
        if (active >= 1) {
            int sx = sl[cur_slot].sx >= 0 ? sl[cur_slot].sx : sl[cur_slot].x, sy = sl[cur_slot].sy >= 0 ? sl[cur_slot].sy : sl[cur_slot].y;
            gconf_load();
            /* bottom-edge back: its own switch, and off while an excluded app (WeRead: swipe-up = toolbar) is in front */
            int eb = EDGE_BACK && G_EDGE_BACK && active == 1 && sy > H - EDGE && !back_excluded();
            /* gestures off: everything goes to Android except a swipe that starts in the bottom edge (back stays) */
            if (!gest && !eb) { for (int i = 0; i < n; i++) forward(&fr[i]); break; }
            t_down = now_ms();
            for (int i = 0; i < n && nheld < MAXEV; i++) held[nheld++] = fr[i];
            { static long last_poke = 0; if (t_down - last_poke > 20000) { last_poke = t_down; action("poke", NULL); } }   /* keep the Kindle from sleeping while the screen is being used */
            corner_fired = 0;
            two_done = 0;
            if (active >= 2 && !two_any()) {    /* every two-finger gesture off: Android gets them (pinch) */
                flush_held(); md = PASS;
            } else if (active >= 2) {       /* both fingers landed in the same frame */
                nheld = 0;
                md = TWO; two_t0 = now_ms();
                two_begin();
            } else if (eb) md = EDGE_B;
            else if (gest && G_EDGE_PANEL && sy < (EDGE_TOP >= 0 ? EDGE_TOP : EDGE)) md = EDGE_T;
            else md = PENDING;
            (void)sx;
        } else {
            for (int i = 0; i < n; i++) forward(&fr[i]);
        }
        break;
    case PENDING:
        if (active >= 2 && !two_any()) {
            for (int i = 0; i < n && nheld < MAXEV; i++) held[nheld++] = fr[i];
            flush_held(); md = PASS;
        } else if (active >= 2) {
            nheld = 0;                      /* two fingers: swallow what we held */
            md = TWO; two_t0 = now_ms();
            two_begin();
        } else if (active == 0) {
            for (int i = 0; i < n && nheld < MAXEV; i++) held[nheld++] = fr[i];
            flush_held(); md = IDLE;
        } else if (now_ms() - t_down >= WINDOW_MS) {
            for (int i = 0; i < n && nheld < MAXEV; i++) held[nheld++] = fr[i];
            flush_held(); md = PASS;
        } else {
            for (int i = 0; i < n && nheld < MAXEV; i++) held[nheld++] = fr[i];
        }
        break;
    case PASS: {
        for (int i = 0; i < n; i++) forward(&fr[i]);
        if (active >= 2) {                  /* a second finger arriving late: let Android have it (pinch etc.) */
        }
        if (active == 0) {
            /* remember the gesture direction for the next page change: horizontal swipe -> left/right,
               vertical swipe -> up/down, short tap -> which half of the screen */
            if (!corner_fired && sl[cur_slot].sx >= 0 && now_ms() - t_down < 800) {
                int dx = sl[cur_slot].x - sl[cur_slot].sx;
                int dy = sl[cur_slot].y - sl[cur_slot].sy;
                if (abs(dx) > 80 && abs(dx) > abs(dy)) epd_dir(dx < 0 ? 2 : 3);
                else if (abs(dy) > 80 && abs(dy) > abs(dx)) epd_dir(dy < 0 ? 1 : 0);
                else if (abs(dx) < 40 && abs(dy) < 40) epd_dir(sl[cur_slot].sx > W / 2 ? 2 : 3);
            }
            md = IDLE;
            break;
        }
        const char *cn;
        if (!corner_fired && CORNER_MS > 0 && active == 1 && now_ms() - t_down >= CORNER_MS && in_corner(sl[cur_slot].x, sl[cur_slot].y, &cn)
            && abs(sl[cur_slot].x - sl[cur_slot].sx) < 40 && abs(sl[cur_slot].y - sl[cur_slot].sy) < 40) {
            corner_fired = 1;
            cancel_to_android();
            action(cn, NULL);
            md = SWALLOW;
        }
        break;
    }
    case EDGE_B:
    case EDGE_T: {
        /* a touch that starts in the top/bottom edge strip is held for WINDOW_MS: if it turns into the edge swipe (back / panel)
           it is swallowed, otherwise Android gets it -- a plain tap there must still work */
        int sx = sl[cur_slot].sx >= 0 ? sl[cur_slot].sx : sl[cur_slot].x;
        int sy = sl[cur_slot].sy >= 0 ? sl[cur_slot].sy : sl[cur_slot].y;
        int dx = sl[cur_slot].x - sx;
        int dy = sl[cur_slot].y - sy;
        int swipe = !corner_fired && ((md == EDGE_B && dy < -EDGE_SWIPE) || (md == EDGE_T && dy > EDGE_SWIPE)) && abs(dy) > abs(dx);
        if (active == 0) {
            if (swipe) {                    /* a fast flick that ended before the swipe was seen while held */
                corner_fired = 1;
                if (md == EDGE_B) { logf_("edge swipe up -> back"); back_key(); } else action("panel", NULL);
            } else if (!corner_fired) {     /* a tap: deliver the held press and this release to Android */
                for (int i = 0; i < n && nheld < MAXEV; i++) held[nheld++] = fr[i];
                flush_held();
            }
            md = IDLE; nheld = 0;
        } else if (swipe) {
            corner_fired = 1;               /* fire as soon as the swipe is long enough; the held press never reaches Android */
            nheld = 0;
            if (md == EDGE_B) { logf_("edge swipe up -> back"); back_key(); }
            else action("panel", NULL);
        } else if (!corner_fired) {
            for (int i = 0; i < n && nheld < MAXEV; i++) held[nheld++] = fr[i];
            if (now_ms() - t_down >= EDGE_HOLD_MS || nheld >= MAXEV - 8) {
                flush_held();              /* not a gesture (yet): Android gets the press, the rest of the touch is forwarded */
                edge_kind = md;
                md = EDGE_FWD;
            }
        }
        break;
    }
    case EDGE_FWD: {
        int sx = sl[cur_slot].sx >= 0 ? sl[cur_slot].sx : sl[cur_slot].x;
        int sy = sl[cur_slot].sy >= 0 ? sl[cur_slot].sy : sl[cur_slot].y;
        int dx = sl[cur_slot].x - sx;
        int dy = sl[cur_slot].y - sy;
        for (int i = 0; i < n; i++) forward(&fr[i]);
        if (active == 0) { md = IDLE; break; }
        if (!corner_fired && ((edge_kind == EDGE_B && dy < -EDGE_SWIPE) || (edge_kind == EDGE_T && dy > EDGE_SWIPE)) && abs(dy) > abs(dx)) {
            corner_fired = 1;               /* the swipe turned out to be a gesture after all: take the touch back from Android */
            cancel_to_android();
            if (edge_kind == EDGE_B) { logf_("edge swipe up -> back"); back_key(); }
            else action("panel", NULL);
            md = SWALLOW;
        } else {
            /* corner long press also for touches that started inside the top/bottom edge strip (they are in EDGE_FWD,
               not PASS): same rule as below -- one finger, held >= CORNER_MS, moved < 40 px */
            const char *ecn;
            if (!corner_fired && CORNER_MS > 0 && active == 1 && now_ms() - t_down >= CORNER_MS
                && in_corner(sl[cur_slot].x, sl[cur_slot].y, &ecn) && abs(dx) < 40 && abs(dy) < 40) {
                corner_fired = 1;
                cancel_to_android();
                action(ecn, NULL);
                md = SWALLOW;
            }
        }
        break;
    }
    case TWO:
        if (active == 0) { two_finger_end(); md = IDLE; nheld = 0; }
        else if (!two_done && G_TWO_LONG && now_ms() - two_t0 >= 2000 && abs(sl[two_i[0]].x - two_sx[0]) < 60 && abs(sl[two_i[0]].y - two_sy[0]) < 60) {
            action("invert", NULL); two_done = 1;       /* long press fires while the fingers are still down */
        }
        break;
    case SWALLOW:
        if (active == 0) md = IDLE;
        break;
    }
}

/* ---- protocol A / single touch -> slots (see the header). Only used when the source is not protocol B. ---- */
struct acon { int x, y, major, pres, tid; };   /* one contact of the frame being read; -1 = not sent */
static struct aslot { int used, tid, x, y, major, pres, id; } as_[MAXSLOT];
static int a_next_id = 1;
static int st_btn = 0, st_x = -1, st_y = -1, st_pres = -1;   /* single touch: the last values the driver sent */

/* turn one source frame (ending in SYN_REPORT) into protocol-B events in out[]; returns the count (0: nothing changed) */
static int normalize_frame(const struct input_event *in, int n, struct input_event *out, int max)
{
    struct acon c[MAXSLOT], cur = { -1, -1, -1, -1, -1 };
    int nc = 0, btn_up = 0, nout = 0, any = 0;
    struct input_event other[64];
    int nother = 0;
    struct input_event tmpl;                         /* the SYN_REPORT: every generated event carries its time stamp */
    memset(&tmpl, 0, sizeof(tmpl));
    if (n) tmpl = in[n - 1];
    for (int i = 0; i < n; i++) {
        const struct input_event *e = &in[i];
        if (e->type == EV_SYN && e->code == SYN_MT_REPORT) {
            if (any && nc < MAXSLOT) c[nc++] = cur;
            cur = (struct acon){ -1, -1, -1, -1, -1 }; any = 0;
        } else if (e->type == EV_SYN) {
            continue;                                  /* SYN_REPORT: added at the end; SYN_DROPPED: ignore */
        } else if (e->type == EV_ABS && src_proto == PROTO_A && e->code >= ABS_MT_TOUCH_MAJOR) {
            any = 1;
            if (e->code == ABS_MT_POSITION_X) cur.x = e->value;
            else if (e->code == ABS_MT_POSITION_Y) cur.y = e->value;
            else if (e->code == ABS_MT_TOUCH_MAJOR) cur.major = e->value;
            else if (e->code == ABS_MT_PRESSURE) cur.pres = e->value;
            else if (e->code == ABS_MT_TRACKING_ID) cur.tid = e->value;
        } else if (e->type == EV_ABS && (e->code == ABS_X || e->code == ABS_Y || e->code == ABS_PRESSURE)) {
            if (src_proto == PROTO_ST) {
                if (e->code == ABS_X) st_x = e->value; else if (e->code == ABS_Y) st_y = e->value; else st_pres = e->value;
            }                                          /* A: the driver's single-touch copy, the slots replace it */
        } else {
            if (e->type == EV_KEY && e->code == BTN_TOUCH) {
                if (!e->value) btn_up = 1;
                if (src_proto == PROTO_ST) st_btn = e->value;
            }
            if (nother < 64) other[nother++] = *e;
        }
    }
    if (any && nc < MAXSLOT) c[nc++] = cur;            /* last contact without its SYN_MT_REPORT */
    if (src_proto == PROTO_ST) {
        nc = 0;
        int down = src_btn_touch ? st_btn : st_pres > 0;
        if (down && st_x >= 0 && st_y >= 0) { c[0] = (struct acon){ st_x, st_y, -1, st_pres, 0 }; nc = 1; }
    } else {
        int k = 0;                                     /* pressure 0 = lifted; BTN_TOUCH 0 = everything lifted */
        for (int i = 0; i < nc; i++) if (!btn_up && c[i].pres != 0) c[k++] = c[i];
        nc = k;
    }
    /* match contacts to the slots of the previous frame */
    int cslot[MAXSLOT], taken[MAXSLOT];
    memset(taken, 0, sizeof(taken));
    for (int i = 0; i < nc; i++) cslot[i] = -1;
    for (int i = 0; i < nc; i++)                       /* by the driver's tracking id */
        if (c[i].tid >= 0)
            for (int s = 0; s < MAXSLOT; s++)
                if (as_[s].used && !taken[s] && as_[s].tid == c[i].tid) { cslot[i] = s; taken[s] = 1; break; }
    long lim = (long)(W > H ? W : H) / 3; lim *= lim;
    for (;;) {                                         /* the rest: nearest neighbour, closest pair first */
        long best = -1; int bi = -1, bs = -1;
        for (int i = 0; i < nc; i++) {
            if (cslot[i] >= 0) continue;
            int x = c[i].x, y = c[i].y;
            for (int s = 0; s < MAXSLOT; s++) {
                if (!as_[s].used || taken[s]) continue;
                if (c[i].tid >= 0 && as_[s].tid >= 0) continue;   /* both have ids and they differ: not the same finger */
                long dx = (x >= 0 ? x : as_[s].x) - as_[s].x, dy = (y >= 0 ? y : as_[s].y) - as_[s].y, d = dx * dx + dy * dy;
                if (d <= lim && (best < 0 || d < best)) { best = d; bi = i; bs = s; }
            }
        }
        if (bi < 0) break;
        cslot[bi] = bs; taken[bs] = 1;
    }
#define OUT(t, cd, v) do { if (nout < max - 1) { out[nout] = tmpl; out[nout].type = (t); out[nout].code = (cd); out[nout].value = (v); nout++; } } while (0)
    for (int s = 0; s < MAXSLOT; s++)                  /* fingers that are gone */
        if (as_[s].used && !taken[s]) {
            OUT(EV_ABS, ABS_MT_SLOT, s); OUT(EV_ABS, ABS_MT_TRACKING_ID, -1);
            as_[s].used = 0;
        }
    for (int i = 0; i < nc; i++) {
        int s = cslot[i], fresh = 0;
        if (s < 0) {                                   /* a new finger: the lowest free slot */
            for (s = 0; s < MAXSLOT && (as_[s].used || taken[s]); s++) ;
            if (s >= MAXSLOT) continue;
            if (c[i].x < 0 || c[i].y < 0) continue;    /* no position yet: wait for one */
            taken[s] = 1; fresh = 1;
            as_[s] = (struct aslot){ 1, c[i].tid, -1, -1, -1, -1, a_next_id };
            a_next_id = a_next_id >= 65535 ? 1 : a_next_id + 1;
        }
        struct aslot *a = &as_[s];
        int hdr = 0;
#define SLOTHDR() do { if (!hdr) { OUT(EV_ABS, ABS_MT_SLOT, s); hdr = 1; } } while (0)
        if (fresh) { SLOTHDR(); OUT(EV_ABS, ABS_MT_TRACKING_ID, a->id); }
        a->tid = c[i].tid;
        if (c[i].x >= 0 && c[i].x != a->x) { SLOTHDR(); OUT(EV_ABS, ABS_MT_POSITION_X, c[i].x); a->x = c[i].x; }
        if (c[i].y >= 0 && c[i].y != a->y) { SLOTHDR(); OUT(EV_ABS, ABS_MT_POSITION_Y, c[i].y); a->y = c[i].y; }
        if (c[i].major >= 0 && c[i].major != a->major) { SLOTHDR(); OUT(EV_ABS, ABS_MT_TOUCH_MAJOR, c[i].major); a->major = c[i].major; }
        if (src_proto == PROTO_A && c[i].pres >= 0 && c[i].pres != a->pres) { SLOTHDR(); OUT(EV_ABS, ABS_MT_PRESSURE, c[i].pres); a->pres = c[i].pres; }
#undef SLOTHDR
    }
    for (int i = 0; i < nother; i++) OUT(other[i].type, other[i].code, other[i].value);
    if (!nout) return 0;
    out[nout] = tmpl; out[nout].type = EV_SYN; out[nout].code = SYN_REPORT; out[nout].value = 0;
    return nout + 1;
#undef OUT
}

static int setup_uinput_touch(void)
{
    ufd = open("/dev/input/uinput", O_WRONLY | O_NONBLOCK);
    if (ufd < 0) ufd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (ufd < 0) { perror("uinput"); return -1; }
    ioctl(ufd, UI_SET_EVBIT, EV_SYN);
    ioctl(ufd, UI_SET_EVBIT, EV_KEY);
    ioctl(ufd, UI_SET_KEYBIT, BTN_TOUCH);
    ioctl(ufd, UI_SET_EVBIT, EV_ABS);
    ioctl(ufd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);
    static const int codes[] = { ABS_MT_SLOT, ABS_MT_TRACKING_ID, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TOUCH_MAJOR, ABS_MT_PRESSURE };
    struct uinput_user_dev dev;
    memset(&dev, 0, sizeof(dev));
    snprintf(dev.name, UINPUT_MAX_NAME_SIZE, "veradroid-touch");
    dev.id.bustype = BUS_VIRTUAL; dev.id.vendor = 0x1d6b; dev.id.product = 0x0001; dev.id.version = 1;
    for (unsigned i = 0; i < sizeof(codes) / sizeof(codes[0]); i++) {
        struct input_absinfo ai;
        if (ioctl(tfd, EVIOCGABS(codes[i]), &ai) < 0) continue;       /* the source device does not have it */
        if (codes[i] == ABS_MT_POSITION_X) { sx_min = ai.minimum; sx_max = ai.maximum; }
        if (codes[i] == ABS_MT_POSITION_Y) { sy_min = ai.minimum; sy_max = ai.maximum; }
        ioctl(ufd, UI_SET_ABSBIT, codes[i]);
        dev.absmin[codes[i]] = ai.minimum; dev.absmax[codes[i]] = ai.maximum;
        if (ROT_ON && codes[i] == ABS_MT_POSITION_X) { dev.absmin[codes[i]] = 0; dev.absmax[codes[i]] = W - 1; }   /* logical pixels */
        if (ROT_ON && codes[i] == ABS_MT_POSITION_Y) { dev.absmin[codes[i]] = 0; dev.absmax[codes[i]] = H - 1; }
        fprintf(stderr, "abs %d: %d..%d\n", codes[i], dev.absmin[codes[i]], dev.absmax[codes[i]]);
    }
    if (src_proto != PROTO_B) {
        /* protocol A / single touch: the virtual device is protocol B (see the header). Position ranges: the source's MT
           axes (A) or ABS_X / ABS_Y (ST); logical pixels when rotated */
        struct input_absinfo ax, ay;
        int okx = ioctl(tfd, EVIOCGABS(src_proto == PROTO_A ? ABS_MT_POSITION_X : ABS_X), &ax) >= 0;
        int oky = ioctl(tfd, EVIOCGABS(src_proto == PROTO_A ? ABS_MT_POSITION_Y : ABS_Y), &ay) >= 0;
        if (!okx) { ax.minimum = 0; ax.maximum = W - 1; }
        if (!oky) { ay.minimum = 0; ay.maximum = H - 1; }
        sx_min = ax.minimum; sx_max = ax.maximum; sy_min = ay.minimum; sy_max = ay.maximum;
        const int syn[4] = { ABS_MT_SLOT, ABS_MT_TRACKING_ID, ABS_MT_POSITION_X, ABS_MT_POSITION_Y };
        const int smin[4] = { 0, 0, ROT_ON ? 0 : ax.minimum, ROT_ON ? 0 : ay.minimum };
        const int smax[4] = { MAXSLOT - 1, 65535, ROT_ON ? W - 1 : ax.maximum, ROT_ON ? H - 1 : ay.maximum };
        for (int i = 0; i < 4; i++) {
            ioctl(ufd, UI_SET_ABSBIT, syn[i]);
            dev.absmin[syn[i]] = smin[i]; dev.absmax[syn[i]] = smax[i];
            fprintf(stderr, "abs %d: %d..%d (proto %s)\n", syn[i], smin[i], smax[i], src_proto == PROTO_A ? "A" : "ST");
        }
    } else if (ROT_ON) {
        /* single-touch panels (PW5 goodix: ABS_X / ABS_Y + BTN_TOUCH) are only run through here when rotated */
        static const int st[] = { ABS_X, ABS_Y, ABS_PRESSURE };
        for (unsigned i = 0; i < sizeof(st) / sizeof(st[0]); i++) {
            struct input_absinfo ai;
            if (ioctl(tfd, EVIOCGABS(st[i]), &ai) < 0) continue;
            ioctl(ufd, UI_SET_ABSBIT, st[i]);
            dev.absmin[st[i]] = st[i] == ABS_X || st[i] == ABS_Y ? 0 : ai.minimum;
            dev.absmax[st[i]] = st[i] == ABS_X ? W - 1 : st[i] == ABS_Y ? H - 1 : ai.maximum;
            fprintf(stderr, "abs %d: %d..%d\n", st[i], dev.absmin[st[i]], dev.absmax[st[i]]);
        }
    }
    if (write(ufd, &dev, sizeof(dev)) < 0) { perror("uinput write"); return -1; }
    if (ioctl(ufd, UI_DEV_CREATE) < 0) { perror("UI_DEV_CREATE"); return -1; }
    return 0;
}

static int setup_uinput_keys(void)
{
    kfd = open("/dev/input/uinput", O_WRONLY | O_NONBLOCK);
    if (kfd < 0) kfd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (kfd < 0) return -1;
    ioctl(kfd, UI_SET_EVBIT, EV_KEY);
    ioctl(kfd, UI_SET_EVBIT, EV_SYN);
    static const int keys[] = { KEY_BACK, KEY_HOME, KEY_MENU, KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_POWER, KEY_PAGEUP, KEY_PAGEDOWN };
    for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) ioctl(kfd, UI_SET_KEYBIT, keys[i]);
    struct uinput_user_dev dev;
    memset(&dev, 0, sizeof(dev));
    snprintf(dev.name, UINPUT_MAX_NAME_SIZE, "veradroid-keys");
    dev.id.bustype = BUS_VIRTUAL; dev.id.vendor = 0x1d6b; dev.id.product = 0x0002; dev.id.version = 1;
    if (write(kfd, &dev, sizeof(dev)) < 0) return -1;
    return ioctl(kfd, UI_DEV_CREATE);
}


/* ---- test hook: "tap x y [hold_ms]" / "swipe x1 y1 x2 y2 ms" written to the --inject FIFO is fed through exactly the same
   code path as a real touch (gesture window, held events, forwarding to Android), so latency and behaviour can be tested
   without a finger ---- */
static void mkev(struct input_event *e, int type, int code, int value)
{
    memset(e, 0, sizeof(*e)); e->type = type; e->code = code; e->value = value;
}
/* a move of a finger that is already down: position only, no tracking id / BTN_TOUCH (the driver resets the start point on those) */
static void inj_move(int x, int y)
{
    struct input_event fr[4];
    int n = 0;
    mkev(&fr[n++], EV_ABS, ABS_MT_SLOT, 0);
    mkev(&fr[n++], EV_ABS, ABS_MT_POSITION_X, x);
    mkev(&fr[n++], EV_ABS, ABS_MT_POSITION_Y, y);
    mkev(&fr[n++], EV_SYN, SYN_REPORT, 0);
    rot_frame(fr, n);
    handle_frame(fr, n);
}
static void inj_frame(int tid, int x, int y)
{
    struct input_event fr[8];
    int n = 0;
    mkev(&fr[n++], EV_ABS, ABS_MT_SLOT, 0);
    mkev(&fr[n++], EV_ABS, ABS_MT_TRACKING_ID, tid);
    if (tid >= 0) { mkev(&fr[n++], EV_ABS, ABS_MT_POSITION_X, x); mkev(&fr[n++], EV_ABS, ABS_MT_POSITION_Y, y); }
    mkev(&fr[n++], EV_KEY, BTN_TOUCH, tid >= 0 ? 1 : 0);
    mkev(&fr[n++], EV_SYN, SYN_REPORT, 0);
    rot_frame(fr, n);
    handle_frame(fr, n);
}
static void inject_cmd(int fd)
{
    char buf[256];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n <= 0) return;
    buf[n] = 0;
    char *save = NULL;
    for (char *line = strtok_r(buf, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        int x1, y1, x2, y2, ms;
        if (sscanf(line, "down %d %d", &x1, &y1) == 2) {
            logf_("inject down %d,%d", x1, y1);
            inj_frame(77, x1, y1);          /* returns at once: the poll tick decides when the press is handed to Android */
        } else if (!strcmp(line, "up")) {
            logf_("inject up");
            inj_frame(-1, 0, 0);
        } else if (sscanf(line, "tap %d %d %d", &x1, &y1, &ms) >= 2) {
            if (sscanf(line, "tap %*d %*d %d", &ms) != 1) ms = 60;
            logf_("inject tap %d,%d", x1, y1);
            inj_frame(77, x1, y1);
            usleep((useconds_t)ms * 1000);
            inj_frame(-1, 0, 0);
        } else if (sscanf(line, "swipe %d %d %d %d %d", &x1, &y1, &x2, &y2, &ms) == 5) {
            logf_("inject swipe %d,%d -> %d,%d", x1, y1, x2, y2);
            int steps = 12;
            for (int i = 0; i <= steps; i++) {
                int x = x1 + (x2 - x1) * i / steps, y = y1 + (y2 - y1) * i / steps;
                if (i == 0) inj_frame(78, x, y);            /* the tracking id is sent once, at touch-down, like the real panel */
                else inj_move(x, y);
                usleep((useconds_t)(ms * 1000 / steps));
            }
            inj_frame(-1, 0, 0);
        }
    }
}

/* gesture_tap (see the header): every key press is one bezel double tap */
static void tap_read(void)
{
    struct input_event ev;
    for (;;) {
        ssize_t n = read(tapfd, &ev, sizeof(ev));
        if (n == (ssize_t)sizeof(ev)) {
            if (ev.type != EV_KEY || ev.value != 1) continue;
            gconf_load();
            if (paused || !G_TAP || (FLAGF && access(FLAGF, F_OK) == 0)) { logf_("tap key %d ignored", ev.code); continue; }
            logf_("bezel tap (key %d) -> key %d", ev.code, G_TAP_KEY);
            key_tap(G_TAP_KEY);
            continue;
        }
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) return;
        logf_("tapdev gone (%s), bezel tap off", n < 0 ? strerror(errno) : "eof");   /* gesturetapd restarted: rescan on the next start */
        close(tapfd); tapfd = -1;
        return;
    }
}

int main(int argc, char **argv)
{
    const char *dev = NULL;
    int pos = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--w") && i + 1 < argc) W = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--h") && i + 1 < argc) H = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--edge") && i + 1 < argc) EDGE = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--edge-top") && i + 1 < argc) EDGE_TOP = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--debug")) TOUCH_DEBUG = 1;
        else if (!strcmp(argv[i], "--window") && i + 1 < argc) WINDOW_MS = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--corner") && i + 1 < argc) CORNER = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--corner-ms") && i + 1 < argc) CORNER_MS = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--edge-hold") && i + 1 < argc) EDGE_HOLD_MS = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--edge-swipe") && i + 1 < argc) EDGE_SWIPE = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--edge-back") && i + 1 < argc) EDGE_BACK = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--no-gestures")) GESTURES = 0;
        else if (!strcmp(argv[i], "--flag") && i + 1 < argc) FLAGF = argv[++i];
        else if (!strcmp(argv[i], "--inject") && i + 1 < argc) INJECT = argv[++i];
        else if (!strcmp(argv[i], "--gconf") && i + 1 < argc) GCONF = argv[++i];
        else if (!strcmp(argv[i], "--fg") && i + 1 < argc) FGF = argv[++i];
        else if (!strcmp(argv[i], "--rotate") && i + 1 < argc) { ROT = atoi(argv[++i]); ROT_ON = 1; }
        else if (!strcmp(argv[i], "--vw") && i + 1 < argc) VW = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--tapdev") && i + 1 < argc) TAPDEV = argv[++i];
        else if (!strcmp(argv[i], "--proto") && i + 1 < argc) {
            const char *v = argv[++i];
            proto_forced = !strcmp(v, "a") || !strcmp(v, "A") ? PROTO_A : !strcmp(v, "st") || !strcmp(v, "ST") ? PROTO_ST : PROTO_B;
        }
        else if (pos == 0) { dev = argv[i]; pos++; }
        else if (pos == 1) { LOGF = argv[i]; pos++; }
        else if (pos == 2) { ACT = argv[i]; pos++; }
    }
    if (!dev) { fprintf(stderr, "usage: %s <touch-event-dev> <log-file> <action-script> [opts]\n", argv[0]); return 2; }
    PW = W; PH = H;
    if (VW <= 0 || VW > PW) VW = PW;
    if (ROT_ON) {
        if (ROT != 90 && ROT != 180 && ROT != 270) ROT = 0;
        if (ROT == 90 || ROT == 270) { W = PH; H = VW; }   /* from here on W / H are the logical (Android) size */
    }
    signal(SIGINT, on_sig); signal(SIGTERM, on_sig); signal(SIGCHLD, SIG_IGN);
    signal(SIGUSR1, on_usr1); signal(SIGUSR2, on_usr2);

    tfd = open(dev, O_RDONLY);
    if (tfd < 0) { perror("open touch"); return 1; }
    {
        unsigned long keybits[(KEY_MAX / (8 * sizeof(unsigned long))) + 2];
        memset(keybits, 0, sizeof(keybits));
        if (ioctl(tfd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits) >= 0)
            src_btn_touch = (keybits[BTN_TOUCH / (8 * sizeof(unsigned long))] >> (BTN_TOUCH % (8 * sizeof(unsigned long)))) & 1;
        /* which multitouch protocol (see the header): ABS_MT_SLOT -> B, MT positions only -> A, ABS_X / ABS_Y only -> ST */
        unsigned long absbits[(ABS_MAX / (8 * sizeof(unsigned long))) + 2];
        memset(absbits, 0, sizeof(absbits));
#define HASABS(c) ((absbits[(c) / (8 * sizeof(unsigned long))] >> ((c) % (8 * sizeof(unsigned long)))) & 1)
        if (ioctl(tfd, EVIOCGBIT(EV_ABS, sizeof(absbits)), absbits) >= 0 && !HASABS(ABS_MT_SLOT))
            src_proto = HASABS(ABS_MT_POSITION_X) ? PROTO_A : HASABS(ABS_X) ? PROTO_ST : PROTO_B;
#undef HASABS
        if (proto_forced >= 0) src_proto = proto_forced;
    }
    if (setup_uinput_touch() < 0) return 1;
    if (setup_uinput_keys() < 0) fprintf(stderr, "warning: no keys device\n");
    if (ioctl(tfd, EVIOCGRAB, 1) < 0) perror("EVIOCGRAB");     /* from now on only we see the touches */
    if (TAPDEV && TAPDEV[0]) {
        tapfd = open(TAPDEV, O_RDONLY | O_NONBLOCK);
        if (tapfd < 0) fprintf(stderr, "tapdev %s: %s\n", TAPDEV, strerror(errno));
        else if (ioctl(tapfd, EVIOCGRAB, 1) < 0) perror("EVIOCGRAB tapdev");
    }
    if (EDGE_TOP < 0) EDGE_TOP = EDGE;
    EDGE_BASE = EDGE; EDGE_TOP_BASE = EDGE_TOP; EDGE_SWIPE_BASE = EDGE_SWIPE;
    int ifd = -1;
    if (INJECT) { mkfifo(INJECT, 0600); ifd = open(INJECT, O_RDWR | O_NONBLOCK); }
    gconf_load();
    logf_("started: dev=%s %dx%d edge=%d window=%dms corner=%d/%dms gestures=%d", dev, W, H, EDGE, WINDOW_MS, CORNER, CORNER_MS, GESTURES);
    if (src_proto != PROTO_B) logf_("source is %s: converted to slots", src_proto == PROTO_A ? "multitouch protocol A" : "single touch");
    if (ROT_ON) logf_("rotate %d: panel %dx%d (visible width %d) -> logical %dx%d", ROT, PW, PH, VW, W, H);

    struct input_event frame[MAXEV];
    int nf = 0, dropping = 0;
    while (!quit) {
        if (want_release) {
            want_release = 0;
            if (!paused) { cancel_to_android(); ioctl(tfd, EVIOCGRAB, 0); if (tapfd >= 0) ioctl(tapfd, EVIOCGRAB, 0); paused = 1; md = IDLE; nheld = 0; nf = 0; memset(sl, 0, sizeof(sl)); memset(as_, 0, sizeof(as_)); st_btn = 0; logf_("released"); }
        }
        if (want_grab) {
            want_grab = 0;
            if (paused) { ioctl(tfd, EVIOCGRAB, 1); if (tapfd >= 0) ioctl(tapfd, EVIOCGRAB, 1); paused = 0; md = IDLE; nheld = 0; nf = 0; memset(sl, 0, sizeof(sl)); memset(as_, 0, sizeof(as_)); st_btn = 0; logf_("grabbed again"); }
        }
        struct pollfd pf[3] = { { tfd, POLLIN, 0 }, { ifd, POLLIN, 0 }, { tapfd, POLLIN, 0 } };
        int pr = poll(pf, 3, md == IDLE ? -1 : 10);   /* a negative fd is skipped by poll */
        if (pr > 0 && tapfd >= 0 && (pf[2].revents & (POLLIN | POLLERR | POLLHUP))) {
            tap_read();
            if (!(pf[0].revents & POLLIN) && !(ifd >= 0 && (pf[1].revents & POLLIN))) continue;
        }
        if (pr > 0 && ifd >= 0 && (pf[1].revents & POLLIN)) { inject_cmd(ifd); if (!(pf[0].revents & POLLIN)) continue; }   /* nothing to time while idle: sleep until a touch or a signal */
        if (pr == 0) {
            /* idle tick: lets PENDING expire and long presses fire without new events */
            if (md == PENDING && now_ms() - t_down >= WINDOW_MS) {
                if (count_active() >= 2 && two_any()) {
                    nheld = 0; md = TWO; two_t0 = now_ms();
                    two_begin();
                } else { flush_held(); md = PASS; }
            }
            if ((md == EDGE_B || md == EDGE_T) && !corner_fired && count_active() == 1 && now_ms() - t_down >= EDGE_HOLD_MS) {
                flush_held();                    /* held still in the edge strip (long press there): let Android have it now */
                edge_kind = md;
                md = EDGE_FWD;
            }
            if (md == TWO && !two_done && G_TWO_LONG && now_ms() - two_t0 >= 2000 && abs(sl[two_i[0]].x - two_sx[0]) < 60 && abs(sl[two_i[0]].y - two_sy[0]) < 60) {
                action("invert", NULL); two_done = 1;
            }
            if (md == PASS && !corner_fired && CORNER_MS > 0 && count_active() == 1 && now_ms() - t_down >= CORNER_MS) {
                const char *cn;
                if (in_corner(sl[cur_slot].x, sl[cur_slot].y, &cn)) { corner_fired = 1; cancel_to_android(); action(cn, NULL); md = SWALLOW; }
            }
            /* the same for a touch that started in the top / bottom edge strip and was handed to Android (EDGE_FWD): a finger
               held still sends no events, so only this tick sees the time run out. Same rule as handle_frame's EDGE_FWD
               branch (moved < 40 px) */
            if (md == EDGE_FWD && !corner_fired && CORNER_MS > 0 && count_active() == 1 && now_ms() - t_down >= CORNER_MS) {
                const char *cn;
                int sx = sl[cur_slot].sx >= 0 ? sl[cur_slot].sx : sl[cur_slot].x, sy = sl[cur_slot].sy >= 0 ? sl[cur_slot].sy : sl[cur_slot].y;
                if (in_corner(sl[cur_slot].x, sl[cur_slot].y, &cn) && abs(sl[cur_slot].x - sx) < 40 && abs(sl[cur_slot].y - sy) < 40) {
                    corner_fired = 1; cancel_to_android(); action(cn, NULL); md = SWALLOW;
                }
            }
            continue;
        }
        if (pr < 0) { if (errno == EINTR) continue; break; }
        /* read everything that is queued in one call: one event per read() kept a starved single-core reader even further
           behind the 64-event evdev buffer of the 3.0 kernels */
        static struct input_event rb[64];
        ssize_t n = read(tfd, rb, sizeof(rb));
        if (n < (ssize_t)sizeof(rb[0])) { if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue; break; }
        if (paused) { nf = 0; dropping = 0; continue; }
        for (int k = 0; k < (int)(n / (ssize_t)sizeof(rb[0])); k++) {
            struct input_event e = rb[k];
            if (e.type == EV_SYN && e.code == SYN_DROPPED) {
                /* the kernel lost events: throw away the partial frame and everything up to the next SYN_REPORT,
                   then take the finger state from the kernel (evdev's documented recovery) */
                nf = 0; dropping = 1; drops++;
                continue;
            }
            if (e.type == EV_SYN && e.code == SYN_REPORT) {
                if (dropping) { dropping = 0; nf = 0; resync_slots(1); continue; }
                if (nf < MAXEV) frame[nf++] = e;
                if (src_proto == PROTO_B) {
                    if (new_touch_over_active(frame, nf)) resync_slots(0);
                    rot_frame(frame, nf);
                    handle_frame(frame, nf);
                } else {
                    static struct input_event conv[MAXEV];
                    int nc = normalize_frame(frame, nf, conv, MAXEV);
                    if (nc) { rot_frame(conv, nc); handle_frame(conv, nc); }
                }
                nf = 0;
            } else if (!dropping && nf < MAXEV - 1) frame[nf++] = e;
        }
    }
    ioctl(tfd, EVIOCGRAB, 0);
    if (tapfd >= 0) ioctl(tapfd, EVIOCGRAB, 0);
    ioctl(ufd, UI_DEV_DESTROY);
    if (kfd >= 0) ioctl(kfd, UI_DEV_DESTROY);
    logf_("stopped, forwarded %lu events, %lu drops, %lu stuck fingers lifted, %lu BTN_TOUCH fixed", fwd_count, drops, resync_lifts, btn_fixes);
    return 0;
}
