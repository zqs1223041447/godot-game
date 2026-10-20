"""Verify original archive, replace only HTML, and stage the launcher bundle."""
import hashlib,json,pathlib,re,shutil,subprocess,sys
root=pathlib.Path(__file__).resolve().parent
repo=root.parent
out=pathlib.Path(sys.argv[1]).resolve()
m=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
if out.exists(): raise ValueError('Output must not already exist')
subprocess.run([sys.executable,str(repo/'web-release/rebuild.py'),str(out/'original')],check=True)
archive=out/'original/godot-game-web.zip'
assert hashlib.sha256(archive.read_bytes()).hexdigest()==m['original_zip_sha256']
html=(root/'index.html').read_bytes()
assert hashlib.sha256(html).hexdigest()==m['index_html_sha256']
# Ensure the browser code is the same actual shell source exercised by Node tests.
template=(root/'web/shell.html').read_text(encoding='utf-8')
actual_inline=re.findall(r'<script>([\s\S]*?)</script>',html.decode())
source_inline=re.findall(r'<script>([\s\S]*?)</script>',template)
assert len(actual_inline)==len(source_inline)==1
config=re.search(r'  const config = (.*);',actual_inline[0]).group(1)
json.loads(config)
expected_inline=source_inline[0].replace('$GODOT_CONFIG',config).replace('$GODOT_THREADS_ENABLED','false')
assert actual_inline[0]==expected_inline,'Generated HTML does not match tested startup shell'
assert (out/'original/web/single_instance_gate.js').read_bytes()==(root/'web/single_instance_gate.js').read_bytes(),'Gate source mismatch'
web=out/'bundle';shutil.copytree(out/'original/web',web)
(web/'.nojekyll').unlink()
(web/'index.html').write_bytes(html)
shutil.copyfile(root/'README.zh-CN.txt',web/'README.zh-CN.txt')
print('Verified original assets; replaced only index.html and added launch instructions')
