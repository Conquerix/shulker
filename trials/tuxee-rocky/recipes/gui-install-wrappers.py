import pathlib,os,subprocess
p=pathlib.Path('/opt/tuxee-gui')
for t in ['tuxee-Xvnc','tuxee-vncpasswd','matchbox-window-manager','dbus-daemon']:
 f=pathlib.Path('/usr/local/bin')/t
 f.write_text('#!/bin/sh\nexport LD_LIBRARY_PATH=/opt/tuxee-gui/lib:/opt/tuxee-gui/lib64:/opt/tuxee-gui/deps\nexec /opt/tuxee-gui/bin/'+t+' "$@"\n');f.chmod(0o755)
# xkbcomp is launched by Xvnc, its libraries inherit the above scope.
subprocess.run(['/usr/local/bin/tuxee-Xvnc','-version'],check=True)
