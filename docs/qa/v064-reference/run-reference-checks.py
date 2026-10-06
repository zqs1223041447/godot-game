#!/usr/bin/env python3
"""Bounded v64 reference generation receipts. No imports or mechanism reruns."""
import argparse, hashlib, json, os, selectors, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
QA=Path(__file__).resolve().parent
ERRORS=('SCRIPT ERROR','ERROR:','Assertion','Traceback','Parse Error')
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(name,data):
    with (QA/name).open('x') as f: json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n')
def inputs(stage):
    if stage=='export':
        paths=[ROOT/'project.godot',ROOT/'tools/export_reference.gd',ROOT/'tools/export_source_execution_coverage.gd']
        paths+=list((ROOT/'scripts').rglob('*.gd'))+list((ROOT/'data').rglob('*.json'))
    elif stage=='build':paths=[ROOT/p for p in ['tools/build_reference.py','docs/reference/catalog.json','docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json']]
    else:paths=[QA/'check-reference.py',ROOT/'docs/reference/catalog.json',ROOT/'docs/reference/index.html',ROOT/'docs/reference/source-tree-coverage.json']
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(paths))}
def run(stage,label,command,env=None):
    before=inputs(stage);save(label+'-input-sha256.json',before)
    started=time.monotonic();output={'stdout':[],'stderr':[]};abort=None
    process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    selector=selectors.DefaultSelector()
    for name in output:selector.register(getattr(process,name),selectors.EVENT_READ,name)
    while selector.get_map():
        if time.monotonic()-started>120 and process.poll() is None:abort='timeout';process.kill()
        for key,_ in selector.select(.1):
            line=key.fileobj.readline()
            if not line:selector.unregister(key.fileobj);continue
            output[key.data].append(line)
            if any(marker in line for marker in ERRORS) and process.poll() is None and command[0].endswith('godot'):abort='first_error_line';process.terminate()
    code=process.wait();selector.close()
    for name,lines in output.items():
        with (QA/(label+'.'+name+'.log.txt')).open('x') as f:f.writelines(lines)
    after=inputs(stage)
    report={'command':command,'exit_code':code,'stopped_on':abort,'seconds':round(time.monotonic()-started,3),'error_lines':[line.strip() for lines in output.values() for line in lines if any(x in line for x in ERRORS)],'source_changed_during_run':[name for name in before.keys()|after.keys() if before.get(name)!=after.get(name)]}
    save(label+'-result.json',report);print(json.dumps(report,ensure_ascii=False),flush=True)
    if code!=0 or report['error_lines'] or report['source_changed_during_run']:raise SystemExit(1)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['export','build','verify']);parser.add_argument('--prefix',default='');args=parser.parse_args()
    if args.stage=='export':
        directory=tempfile.mkdtemp(prefix='godot-v064-reference-')
        env=dict(os.environ,XDG_DATA_HOME=directory+'/data',XDG_CONFIG_HOME=directory+'/config',XDG_CACHE_HOME=directory+'/cache',GODOT_SILENCE_ROOT_WARNING='1')
        run('export',args.prefix+'godot-export',['/usr/local/bin/godot','--headless','--path',str(ROOT),'--script','res://tools/export_reference.gd'],env)
    elif args.stage=='build':
        for label,command in [('build',['python3','tools/build_reference.py']),('build-check',['python3','tools/build_reference.py','--check'])]:run('build',args.prefix+label,command)
    else:run('verify',args.prefix+'focused-reference',['python3','docs/qa/v064-reference/check-reference.py'])
if __name__=='__main__':main()
