#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void){Display*d=XOpenDisplay(NULL);if(!d){fprintf(stderr,"no display\n");return 1;}int s=DefaultScreen(d);Window w=XCreateSimpleWindow(d,RootWindow(d,s),30,30,640,350,1,BlackPixel(d,s),WhitePixel(d,s));XStoreName(d,w,"Tuxee UBI9 native X11 keyboard probe");XClassHint hint={"tuxee-gui-probe","TuxeeGUIProbe"};XSetClassHint(d,w,&hint);XSelectInput(d,w,ExposureMask|KeyPressMask|StructureNotifyMask);XMapWindow(d,w);XFlush(d);char buf[1024]="";GC gc=XCreateGC(d,w,0,NULL);for(;;){XEvent e;XNextEvent(d,&e);if(e.type==KeyPress){char b[64];KeySym k;int n=XLookupString(&e.xkey,b,63,&k,NULL);if(n>0&&strlen(buf)+n<sizeof(buf)){strncat(buf,b,n);FILE*f=fopen("/workspace/tuxee-accept/gui-input.txt","w");if(f){fputs(buf,f);fclose(f);}char title[1100];snprintf(title,sizeof(title),"Tuxee GUI received: %s",buf);XStoreName(d,w,title);}}XClearWindow(d,w);XDrawString(d,w,gc,30,70,"Native X11 app on UBI9: keyboard input below",43);XDrawString(d,w,gc,30,100,buf,strlen(buf));XFlush(d);}return 0;}
