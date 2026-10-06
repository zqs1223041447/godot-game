#!/usr/bin/env python3
"""Explicit bounded selectors; reuses the two already imported checkouts."""
import argparse, hashlib, json, os, pathlib, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[3]
QA = pathlib.Path(__file__).resolve().parent
SCRIPT = ROOT / 'tests/cold_ailment_duration_gameplay_test.gd'
p = argparse.ArgumentParser()
p.add_argument('selection', choices=['main', 'v081-zero', 'v082-zero'])
p.add_argument('--sections', default='')
p.add_argument('--suffix', default='')
a = p.parse_args()
name = a.selection + a.suffix
project = ROOT.parent / 'v081-map-device-refresh' if a.selection == 'v081-zero' else ROOT
xdg = pathlib.Path(tempfile.mkdtemp(prefix='godot-m1-v082-cold-' + name + '-'))
env = os.environ.copy()
for variable, directory in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
    (xdg / directory).mkdir(); env[variable] = str(xdg / directory)
env['COLD_DURATION_GAMEPLAY_REPORT'] = str(QA / (name + '-result.json'))
if a.selection != 'main': env['COLD_DURATION_ZERO_SOURCE'] = '1'
else: env['COLD_DURATION_FIXTURE_DIR'] = str(QA / 'fixtures')
if a.sections: env['COLD_DURATION_GAMEPLAY_SECTIONS'] = a.sections
cmd = ['godot','--headless','--path',str(project),'--script',str(SCRIPT)]
started=time.monotonic()
with (QA / (name+'.log')).open('w') as log:
    child=subprocess.Popen(cmd,env=env,stdout=log,stderr=subprocess.STDOUT,cwd=project)
    try: code=child.wait(timeout=90)
    except subprocess.TimeoutExpired: child.kill(); code=child.wait()
text=(QA/(name+'.log')).read_text()
record={'command':cmd,'selection':a.selection,'sections':a.sections,'xdg':str(xdg),
        'exit_code':code,'elapsed_seconds':round(time.monotonic()-started,3),
        'test_sha256':hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),
        'errors':[line for line in text.splitlines() if 'ERROR:' in line],
        'log':str(QA/(name+'.log')),'result':env['COLD_DURATION_GAMEPLAY_REPORT']}
(QA/(name+'-run.json')).write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,ensure_ascii=False))
print(text)
raise SystemExit(code if code >= 0 else 1)
