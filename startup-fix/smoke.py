"""Run the real launcher without a browser, on Windows or Linux."""
import pathlib,subprocess,sys,time,urllib.request,urllib.error
exe=pathlib.Path(sys.argv[1]).resolve();root=exe.parent
client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
p=subprocess.Popen([str(exe),'--no-browser'],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
try:
 for _ in range(150):
  if p.poll() is not None: raise AssertionError(p.communicate()[0].decode(errors='replace'))
  try:
   with client.open('http://localhost:18764/',timeout=1) as r: assert r.read()==(root/'index.html').read_bytes()
   break
  except urllib.error.URLError: time.sleep(.1)
 else: raise AssertionError('Launcher did not start on fixed localhost:18764')
 with client.open('http://localhost:18764/index.wasm',timeout=10) as r:
  assert r.headers.get_content_type()=='application/wasm';assert r.read()==(root/'index.wasm').read_bytes()
 try: client.open('http://localhost:18764/README.zh-CN.txt',timeout=2)
 except urllib.error.HTTPError as e: assert e.code==404
 else: raise AssertionError('Non-game file exposed')
 other=subprocess.run([str(exe),'--no-browser'],cwd=root,capture_output=True,timeout=10)
 assert other.returncode==1,(other.returncode,other.stdout,other.stderr)
 assert b'port conflict' in other.stderr,other.stderr
 assert p.poll() is None,'Conflict terminated original launcher'
 print('PASS: real process, exact HTTP bytes, WASM MIME, non-game rejection, conflict exits 1; --no-browser throughout')
finally:
 if p.poll() is None: p.terminate()
 p.communicate(timeout=10)
