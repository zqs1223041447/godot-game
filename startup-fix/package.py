"""Package verified game files and the native Windows build after smoke tests."""
import hashlib,json,pathlib,struct,sys,zipfile
root=pathlib.Path(__file__).resolve().parent
stage=pathlib.Path(sys.argv[1]).resolve();bundle=stage/'bundle'
m=json.loads((root/'manifest.json').read_text())
original=json.loads((root.parent/'web-release/manifest.json').read_text())['web_files']
expected=set(original)|{'Start-Game.exe','README.zh-CN.txt'}
assert {p.name for p in bundle.iterdir()}==expected
for n,v in original.items():
 digest=hashlib.sha256((bundle/n).read_bytes()).hexdigest()
 assert digest==(m['index_html_sha256'] if n=='index.html' else v['sha256']),n
assert (bundle/'README.zh-CN.txt').read_bytes()==(root/'README.zh-CN.txt').read_bytes()
binary=(bundle/'Start-Game.exe').read_bytes();assert binary[:2]==b'MZ'
pe=struct.unpack_from('<I',binary,0x3c)[0];assert binary[pe:pe+4]==b'PE\0\0';assert struct.unpack_from('<H',binary,pe+4)[0]==0x8664
out=stage/'dist';out.mkdir()
archive=out/'godot-game-web-windows-launcher.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for n in sorted(expected):
  info=zipfile.ZipInfo(n,(2026,10,20,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;z.writestr(info,(bundle/n).read_bytes())
with zipfile.ZipFile(archive) as z:
 assert set(z.namelist())==expected and len(z.namelist())==12
 for n in expected: assert z.read(n)==(bundle/n).read_bytes()
sha=hashlib.sha256(archive.read_bytes()).hexdigest()
(out/'SHA256SUMS').write_text(f'{sha}  {archive.name}\n')
(out/'build-manifest.json').write_text(json.dumps({'archive_sha256':sha,'files':{n:hashlib.sha256((bundle/n).read_bytes()).hexdigest() for n in sorted(expected)},'source':m},indent=2)+'\n')
print(sha,archive.name)
