// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * vdkaf: stand in for the Kindle's Java framework on the lipc bus while VeraDroid has stopped it (low-memory mode,
 * KINDLE_UI=nofw, see host/k49/boot/lib/framework.sh).
 *
 * powerd reads the int property "frameworkStarted" of the publisher com.lab126.kaf before it acts on the power
 * button: with the framework gone it thinks the Kindle is still booting and ignores the key, so the device could no
 * longer be put to sleep. This program registers that publisher and answers 1 until it is killed.
 *
 * It only uses three public liblipc entry points (the prototypes below are the ones documented by the openlipc
 * project); liblipc.so itself is the Kindle's own and is looked up at run time, nothing from the firmware is shipped.
 *
 * Build (armhf, dynamic, glibc <= 2.19 so it also starts on older firmware), on a Linux build host:
 *   docker run --rm -v $PWD:/w vdcross-legacy:gcc5-glibc219 arm-linux-gnueabihf-gcc -O2 -Wall -o /w/vdkaf /w/vdkaf.c \
 *       -L/w/kindle-lib -llipc -Wl,--allow-shlib-undefined -Wl,-rpath,/usr/lib
 *   (kindle-lib/liblipc.so: a copy of /usr/lib/liblipc.so.1.0 from any Kindle, needed by the linker only)
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct _LIPC LIPC;
typedef int LIPCcode;                       /* 0 = LIPC_OK */
typedef LIPCcode (*LipcPropCallback)(LIPC *lipc, const char *property, void *value, void *data);
LIPC *LipcOpenEx(const char *service, LIPCcode *code);
void LipcClose(LIPC *lipc);
LIPCcode LipcRegisterIntProperty(LIPC *lipc, const char *property, LipcPropCallback getter, LipcPropCallback setter, void *data);

static volatile sig_atomic_t stop;
static void on_signal(int s) { (void)s; stop = 1; }

static LIPCcode get_started(LIPC *lipc, const char *property, void *value, void *data)
{
    (void)lipc; (void)property; (void)data;
    *(int *)value = 1;
    return 0;
}

int main(void)
{
    LIPCcode code = 0;
    LIPC *h = NULL;
    int i;
    struct sigaction sa;

    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    /* the framework may still be letting go of the name: retry for a few seconds */
    for (i = 0; i < 20 && !stop; i++) {
        h = LipcOpenEx("com.lab126.kaf", &code);
        if (h) break;
        usleep(500000);
    }
    if (!h) { fprintf(stderr, "vdkaf: cannot open com.lab126.kaf (code %d)\n", code); return 1; }
    code = LipcRegisterIntProperty(h, "frameworkStarted", get_started, NULL, NULL);
    if (code != 0) { fprintf(stderr, "vdkaf: cannot register frameworkStarted (code %d)\n", code); LipcClose(h); return 1; }
    fprintf(stderr, "vdkaf: publishing com.lab126.kaf frameworkStarted=1\n");
    while (!stop) pause();
    LipcClose(h);
    return 0;
}
