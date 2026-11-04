import pathlib,subprocess,tarfile,json,hashlib,os
r=pathlib.Path('/trial/gui');r.mkdir(exist_ok=True); src=r/'src';src.mkdir(exist_ok=True)
for p in json.loads((r/'gui-source-lock.json').read_text()):
 a=r/p['file'];assert hashlib.sha256(a.read_bytes()).hexdigest()==p['sha256']
 if not (r/'EXTRACTED').exists() or p['package']=='xfonts-utils':
  with tarfile.open(a) as t:t.extractall(src)
(r/'EXTRACTED').touch()
prefix='/opt/tuxee-gui';os.environ.update(PATH=prefix+'/bin:'+os.environ['PATH'],PKG_CONFIG_PATH=prefix+'/lib/pkgconfig:'+prefix+'/lib64/pkgconfig:'+prefix+'/share/pkgconfig',ACLOCAL_PATH=prefix+'/share/aclocal',LD_LIBRARY_PATH=prefix+'/lib',CFLAGS='-O2',CXXFLAGS='-O2',LDFLAGS='-Wl,-rpath,'+prefix+'/lib')
pathlib.Path(prefix+'/share/aclocal').mkdir(parents=True,exist_ok=True)
def run(cmd,cwd):
 print('RUN',cmd,'IN',cwd,flush=True);subprocess.run(cmd,shell=True,cwd=cwd,check=True)
def build(pattern,flags=''):
 d=next(src.rglob(pattern));
 if (d/'.done').exists():return
 if d.name=='matchbox-window-manager':
  f=d/'configure.ac';text=f.read_text();text=text.replace('\nAM_GCONF_SOURCE_2\n','\n# GConf disabled in this minimal trial build.\n');
  if 'AM_CONDITIONAL(GCONF_SCHEMAS_INSTALL' not in text:text+='\nAM_CONDITIONAL(GCONF_SCHEMAS_INSTALL, false)\n'
  f.write_text(text)
 if not (d/'configure').exists() or d.name=='matchbox-window-manager':run('autoreconf -fi',d)
 if d.name.startswith('bison'):
  (d/'doc/bison.texi').touch();(d/'examples/extracted.stamp').touch()
 if not (d/'config.status').exists():run('./configure --prefix='+prefix+' --disable-static --disable-specs --disable-docs --disable-devel-docs '+flags,d)
 if d.name.startswith('bison'):
  (d/'gui-generated.mk').write_text('include Makefile\n.PHONY: gui-generated\ngui-generated: $(filter lib/% src/%,$(BUILT_SOURCES))\n')
  run('make -j4 -f gui-generated.mk gui-generated',d)
  run('make -j4 src/bison && mkdir -p '+prefix+'/bin && install src/bison '+prefix+'/bin/bison && mkdir -p '+prefix+'/share/bison && cp -a data/. '+prefix+'/share/bison/',d)
 else:run('make -j4 && make install',d)
 (d/'.done').touch()
# Debian native aggregate source contains upstream component archives/directories.
print([p.name for p in src.iterdir()],flush=True)
for agg in ['xutils-dev*','x11-xkb-utils*']:
 for d in src.glob(agg):
  for a in d.rglob('*.tar.*'):
   with tarfile.open(a) as t:t.extractall(src)
build('util-macros*');build('font-util*');build('xtrans*');build('libXdmcp*');build('libXext*');build('libXfixes*');build('libXdamage*');build('libXrandr*');build('libfontenc*');build('libxkbfile*');build('libXfont*','--disable-bzip2')
d=next(src.glob('pixman*'))
if not (d/'.done').exists():
 run('meson setup build --prefix='+prefix+' -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled && ninja -C build && ninja -C build install',d);(d/'.done').touch()
build('bison*','--disable-nls');build('flex*','--disable-nls');build('xkbcomp*')
tiger=next(src.glob('tigervnc-*'));xorg=next(src.glob('xorg-server-*')); xs=tiger/'unix/xserver'
if not (xs/'configure.ac').exists():run('cp -a '+str(xorg)+'/. . && patch -p1 < ../xserver21.patch',xs)
run('cmake -S '+str(tiger)+' -B '+str(r/'tiger-build')+' -DBUILD_VIEWER=OFF -DBUILD_X0VNC=OFF -DCMAKE_PREFIX_PATH=/opt/tuxee-gui -DENABLE_NLS=OFF -DENABLE_H264=OFF -DENABLE_GNUTLS=OFF -DENABLE_NETTLE=OFF -DENABLE_SYSTEMD=OFF -DENABLE_WAYLAND=OFF -DENABLE_SELINUX=OFF -DENABLE_PAM=OFF -DENABLE_PWQUALITY=OFF && cmake --build '+str(r/'tiger-build')+' --parallel 4',r)
run('autoreconf -fi && ./configure --prefix='+prefix+' --disable-glx --disable-glamor --disable-dri --disable-dri2 --disable-dri3 --disable-xorg --disable-xnest --disable-xvfb --disable-xephyr --disable-kdrive --disable-xwin --disable-config-udev --disable-systemd-logind --disable-libdrm --without-dtrace --disable-static --disable-devel-docs --disable-docs --disable-unit-tests --disable-xdmcp --disable-xres --disable-xf86vidmode --disable-xinerama --disable-xv --disable-dpms --disable-screensaver --disable-libunwind --with-default-font-path=built-ins --with-xkb-path=/usr/share/X11/xkb --with-xkb-bin-directory='+prefix+'/bin && make -j4 TIGERVNC_SRCDIR='+str(tiger)+' TIGERVNC_BUILDDIR='+str(r/'tiger-build'),xs)
run('install hw/vnc/Xvnc '+prefix+'/bin/tuxee-Xvnc && install '+str(r/'tiger-build/unix/vncpasswd/vncpasswd')+' '+prefix+'/bin/tuxee-vncpasswd',xs)
build('libmatchbox*','--disable-xft --disable-pango --disable-jpeg');build('matchbox-window-manager*','--disable-xft --disable-startup-notification --disable-session --disable-composite --disable-gconf')
run('ldd '+prefix+'/bin/tuxee-Xvnc',r)
(r/'BUILD-PASSED').touch()
