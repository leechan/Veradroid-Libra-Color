// SPDX-License-Identifier: GPL-3.0-or-later
/* vdwf: waveform timing probe for MediaTek hwtcon (measurement only; pause veradroid-epd with <ctl>/sleep while it runs).
   NEVER pass the scroll flags 0x60 / 0x20 / 0x40: one START + MID + END sequence wedged the driver of a real PW6 until a
   reboot. The program refuses them.
   ops: fill <pat> x y w h | upd <wfm> <full> <flagshex> x y w h | wait | waitall | sleep <ms> | pd <ms> | getpd | fast <0|1> | mark <text>
   pat: 0 white 1 black 2 text-like stripes 3 16-gray ramp 4 inverse stripes 5 mid gray 6 photo-like noise */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <linux/fb.h>
struct r { uint32_t top, left, width, height; };
struct upd { struct r region; uint32_t wfm, mode, marker; int temp; unsigned flags; int dither, quant;
  struct { uint32_t pa, w, h; struct r r; } alt; struct { uint32_t dir, steps; } swipe; uint32_t hbw, hgray, ts1, ts2; };
struct mk { uint32_t marker, collision; };
#define SEND _IOW('F', 0x2E, struct upd)
#define WAITC _IOWR('F', 0x2F, struct mk)
#define SETPD _IOW('F', 0x30, int32_t)
#define GETPD _IOR('F', 0x31, int32_t)
#define SETUF _IOW('F', 0x3B, uint32_t)
#define GETUF _IOWR('F', 0x3C, uint32_t)
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1000.0+t.tv_nsec/1e6;}
int main(int argc,char**argv){
  int fd=open("/dev/fb0",O_RDWR); if(fd<0){perror("fb0");return 1;}
  struct fb_fix_screeninfo fi; struct fb_var_screeninfo vi; ioctl(fd,FBIOGET_FSCREENINFO,&fi); ioctl(fd,FBIOGET_VSCREENINFO,&vi);
  fprintf(stderr,"fb %ux%u virt %ux%u bpp %u stride %u yoff %u len %u\n",vi.xres,vi.yres,vi.xres_virtual,vi.yres_virtual,vi.bits_per_pixel,fi.line_length,vi.yoffset,fi.smem_len);
  uint8_t*fb=mmap(0,fi.smem_len,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0); if(fb==MAP_FAILED){perror("mmap");return 1;}
  fb += (size_t)vi.yoffset*fi.line_length;
  uint32_t marker=0x57460000u+(getpid()&0xff)*256; uint32_t pend[256]; double pt[256]; int np=0; unsigned seed=1;
  for(int i=1;i<argc;){
    if(!strcmp(argv[i],"fill")&&i+5<argc){int p=atoi(argv[i+1]),x=atoi(argv[i+2]),y=atoi(argv[i+3]),w=atoi(argv[i+4]),h=atoi(argv[i+5]);i+=6;
      for(int j=0;j<h;j++){uint8_t*o=fb+(size_t)(y+j)*fi.line_length+x;for(int k=0;k<w;k++){uint8_t v;
        switch(p){case 0:v=255;break;case 1:v=0;break;case 2:v=((j%40)<22&&((k/3+j/7)%5<2))?0:255;break;case 3:v=(uint8_t)((k*16/w)*17);break;
        case 4:v=((j%40)<22&&((k/3+j/7)%5<2))?255:0;break;case 5:v=0x88;break;default:seed=seed*1103515245u+12345u;v=(uint8_t)(((seed>>16)&0xf)*17);break;}
        o[k]=v;}}
    } else if(!strcmp(argv[i],"upd")&&i+7<argc){struct upd u;memset(&u,0,sizeof u);u.wfm=atoi(argv[i+1]);u.mode=atoi(argv[i+2]);u.flags=strtoul(argv[i+3],0,16);
      if(u.flags&0x60){fprintf(stderr,"refusing EPDC_FLAG_SCRLL_* (0x60/0x20/0x40): it wedges hwtcon_v2 until a reboot\n");return 3;}
      u.region.left=atoi(argv[i+4]);u.region.top=atoi(argv[i+5]);u.region.width=atoi(argv[i+6]);u.region.height=atoi(argv[i+7]);i+=8;
      u.marker=++marker;u.temp=0x1000;u.hbw=1;u.hgray=2;if(u.wfm==4){u.hbw=4;u.hgray=4;} if(u.flags&0x2000)u.dither=0x302;
      double t=now();int rc=ioctl(fd,SEND,&u);double t2=now();
      printf("upd wfm=%u full=%u flags=%x %ux%u+%u+%u marker=%x rc=%d errno=%d ioctl=%.1fms\n",u.wfm,u.mode,u.flags,u.region.width,u.region.height,u.region.left,u.region.top,u.marker,rc,rc<0?errno:0,t2-t);
      if(np<256){pend[np]=u.marker;pt[np]=t;np++;}
    } else if(!strcmp(argv[i],"wait")){i++; if(np){struct mk m={pend[np-1],0};int rc=ioctl(fd,WAITC,&m);printf("wait marker=%x rc=%d coll=%u done %.1f ms after submit\n",pend[np-1],rc,m.collision,now()-pt[np-1]);np--;}
    } else if(!strcmp(argv[i],"waitall")){i++; double t0=np?pt[0]:now(); for(int k=0;k<np;k++){struct mk m={pend[k],0};int rc=ioctl(fd,WAITC,&m);printf("  marker=%x rc=%d done %.1f ms after its submit, %.1f after first\n",pend[k],rc,now()-pt[k],now()-t0);} np=0;
    } else if(!strcmp(argv[i],"sleep")&&i+1<argc){usleep(atoi(argv[i+1])*1000);i+=2;
    } else if(!strcmp(argv[i],"pd")&&i+1<argc){int32_t v=atoi(argv[i+1]);int rc=ioctl(fd,SETPD,&v);printf("setpd %d rc=%d\n",v,rc);i+=2;
    } else if(!strcmp(argv[i],"getpd")){int32_t v=-99;int rc=ioctl(fd,GETPD,&v);printf("getpd %d rc=%d\n",v,rc);i++;
    } else if(!strcmp(argv[i],"fast")&&i+1<argc){uint32_t v=(0x80u<<24)|(atoi(argv[i+1])?1:0);int rc=ioctl(fd,SETUF,&v);uint32_t g=0;ioctl(fd,GETUF,&g);printf("fast set rc=%d now=%x\n",rc,g);i+=2;
    } else if(!strcmp(argv[i],"mark")&&i+1<argc){printf("== %s\n",argv[i+1]);i+=2;
    } else {fprintf(stderr,"bad op %s\n",argv[i]);return 2;}
    fflush(stdout);
  }
  return 0;}
