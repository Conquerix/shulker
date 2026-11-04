import ctypes as C,ctypes.util,json,pathlib,urllib.request,hashlib
root=pathlib.Path(__file__).parent
out=root/'sysroot';out.mkdir(exist_ok=True)
a=C.CDLL(ctypes.util.find_library('archive'))
a.archive_read_new.restype=C.c_void_p
a.archive_read_support_filter_all.argtypes=[C.c_void_p];a.archive_read_support_format_all.argtypes=[C.c_void_p]
a.archive_read_open_filename.argtypes=[C.c_void_p,C.c_char_p,C.c_size_t]
a.archive_read_next_header.argtypes=[C.c_void_p,C.POINTER(C.c_void_p)]
a.archive_entry_pathname.argtypes=[C.c_void_p];a.archive_entry_pathname.restype=C.c_char_p
a.archive_entry_symlink.argtypes=[C.c_void_p];a.archive_entry_symlink.restype=C.c_char_p
a.archive_entry_filetype.argtypes=[C.c_void_p];a.archive_entry_filetype.restype=C.c_uint
a.archive_entry_perm.argtypes=[C.c_void_p];a.archive_entry_perm.restype=C.c_int
a.archive_read_data.argtypes=[C.c_void_p,C.c_void_p,C.c_size_t];a.archive_read_data.restype=C.c_ssize_t
a.archive_read_free.argtypes=[C.c_void_p]
names=set('glibc glibc-devel glibc-headers kernel-headers pam libgcc libxcrypt libxcrypt-devel libselinux audit-libs libcap-ng pcre2 openssl-libs libeconf'.split())
for p in json.loads((root/'packages.json').read_text())['available']:
 if p['name'] not in names or p['arch']!='x86_64':continue
 dest=root/(p['name']+'.rpm')
 b=urllib.request.urlopen(p['url'],timeout=60).read();assert hashlib.sha256(b).hexdigest()==p['sha256'];dest.write_bytes(b)
 h=a.archive_read_new();a.archive_read_support_filter_all(h);a.archive_read_support_format_all(h)
 assert a.archive_read_open_filename(h,str(dest).encode(),10240)==0
 entry=C.c_void_p()
 while a.archive_read_next_header(h,C.byref(entry))==0:
  name=a.archive_entry_pathname(entry).decode().removeprefix('./').lstrip('/')
  assert '..' not in pathlib.PurePosixPath(name).parts
  target=out/name;target.parent.mkdir(parents=True,exist_ok=True)
  typ=a.archive_entry_filetype(entry)
  if typ==0o040000:target.mkdir(exist_ok=True)
  elif typ==0o120000:
   link=a.archive_entry_symlink(entry).decode()
   if target.is_symlink():target.unlink()
   if link.startswith('/'):link=str(out/link.lstrip('/'))
   target.symlink_to(link)
  elif typ==0o100000:
   with target.open('wb') as f:
    buf=C.create_string_buffer(65536)
    while (n:=a.archive_read_data(h,buf,len(buf)))>0:f.write(buf.raw[:n])
   target.chmod(a.archive_entry_perm(entry))
 a.archive_read_free(h);print(p['name'],p['version'])
# rpm has /usr/lib64; provide conventional root aliases, without host mutations.
for name in ['lib64','lib']:
 if not (out/name).exists():(out/name).symlink_to('usr/'+name)
 if (out/name).is_dir() and not (out/name).is_symlink():
  for child in (out/'usr'/name).iterdir():
   alias=out/name/child.name
   if not alias.exists() and not alias.is_symlink():alias.symlink_to(child)
headers=out/'usr/include/security';headers.mkdir(exist_ok=True)
for p in (root/'pam-source/libpam/include/security').glob('*.h'):
 (headers/p.name).write_bytes(p.read_bytes())
(out/'usr/lib64/libpam.so').symlink_to('libpam.so.0')
