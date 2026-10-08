"""Linux ACL integration; group permissions must survive a restrictive worker umask."""
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import pytest

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/'system/modules/nixos/services/openhands/prepare-project.sh'

def test_shared_project_setup_is_declared():
    assert SCRIPT.is_file()
    module=(SCRIPT.parent/'default.nix').read_text()
    assert '${./prepare-project.sh}' in module
    assert 'pkgs.acl' in module

@pytest.mark.skipif(sys.platform!='linux' or not shutil.which('setfacl'), reason='Linux ACL runtime acceptance')
def test_new_files_and_worktrees_remain_group_writable():
    # A direct /tmp fixture avoids private pytest parent directories masking the
    # actual ACL result when switching to the independent editor identity.
    with tempfile.TemporaryDirectory(prefix='openhands-acl-') as directory:
        exercise_project(Path(directory))

def exercise_project(tmp_path):
    project=tmp_path/'project';project.mkdir(mode=0o2770);(project/'repository').mkdir();(project/'worktrees').mkdir(mode=0o2770)
    existing=project/'repository'/'existing';existing.write_text('old');existing.chmod(0o600)
    group=10011 if os.geteuid()==0 else os.getgid()
    subprocess.run(['bash',str(SCRIPT),str(project),str(group)],check=True)
    assert existing.stat().st_mode & stat.S_IWGRP
    worktree=project/'worktrees'/'fresh'
    file=worktree/'file'
    def identity(uid,gid):
        def switch():os.setgroups([]);os.setgid(gid);os.setuid(uid)
        return switch
    if os.geteuid()==0:
        tmp_path.chmod(0o755)
        create='import os,sys; from pathlib import Path; os.umask(0o077); p=Path(sys.argv[1]); p.mkdir(); (p/"file").write_text("created by worker")'
        subprocess.run([sys.executable,'-c',create,str(worktree)],preexec_fn=identity(10011,group),check=True)
    else:
        previous=os.umask(0o077)
        try:worktree.mkdir();file.write_text('created by worker')
        finally:os.umask(previous)
    assert worktree.stat().st_mode & stat.S_IWGRP
    assert file.stat().st_mode & stat.S_IWGRP
    assert not file.stat().st_mode & stat.S_IROTH
    # When run by the approved root-only acceptance fixture, prove a different
    # identity in the project group can edit while an unrelated identity cannot.
    if os.geteuid()==0:
        tmp_path.chmod(0o755)
        program='from pathlib import Path; import sys; Path(sys.argv[1]).write_text("edited by VS Code identity")'
        subprocess.run([sys.executable,'-c',program,str(file)],preexec_fn=identity(10013,group),check=True)
        denied=subprocess.run([sys.executable,'-c',program,str(file)],preexec_fn=identity(10014,10014),capture_output=True)
        assert denied.returncode!=0
        private=tmp_path/'provider';private.mkdir(mode=0o700)
        (private/'state').write_text('synthetic private state')
        read='from pathlib import Path; import sys; Path(sys.argv[1]).read_text()'
        denied=subprocess.run([sys.executable,'-c',read,str(private/'state')],preexec_fn=identity(10013,group),capture_output=True)
        assert denied.returncode!=0
