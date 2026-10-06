#!/usr/bin/env python3
"""Immutable, fail-fast v61 reference receipts; exact font runtime inputs only."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[3]
QA=ROOT/'docs/qa/v061-reference'
ERRORS=('SCRIPT ERROR','ERROR:','Assertion','Traceback','Parse Error')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):
    with path.open('x') as stream:json.dump(value,stream,ensure_ascii=False,indent=2);stream.write('\n')
def inputs(stage):
    if stage=='font':
        spec=importlib.util.spec_from_file_location('coverage',ROOT/'tools/check_font_coverage.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        manifest=json.loads((ROOT/module.MANIFEST_PATH).read_text())
        paths=module.runtime_paths(ROOT)+[ROOT/'tools/check_font_coverage.py',ROOT/module.FONT_PATH,ROOT/module.MANIFEST_PATH,ROOT/manifest['license']['path']]
    elif stage=='export':
        seen=set()
        def visit(path):
            if path in seen:return
            seen.add(path)
            if path.suffix!='.gd':return
            for relative in re.findall(r'res://([^"\n]+)',path.read_text()):
                target=ROOT/relative
                if target.is_file() and target.suffix in {'.gd','.json'}:visit(target)
        visit(ROOT/'tools/export_reference.gd')
        seen.update((ROOT/'data').rglob('*.json'));seen.add(ROOT/'project.godot')
        seen.difference_update({ROOT/'docs/reference/catalog.json',ROOT/'docs/reference/source-tree-coverage.json'})
        paths=list(seen)
    elif stage=='build':paths=[ROOT/p for p in ['tools/build_reference.py','docs/reference/catalog.json','docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json','assets/art/equipment/forgeblade.png']]
    else:paths=[ROOT/p for p in ['docs/qa/v061-reference/check-reference.py','docs/qa/v061-reference/v060-baseline.json','docs/reference/catalog.json','docs/reference/index.html','docs/reference/source-tree-coverage.json']]
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(paths)) if p.is_file()}
def run(stage,label,command,env=None):
    before=inputs(stage);save(QA/(label+'-input-sha256.json'),before)
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
            if any(marker in line for marker in ERRORS) and process.poll() is None:
                abort='first_error_line';process.terminate()
    code=process.wait();selector.close()
    for name,lines in output.items():
        with (QA/(label+'.'+name+'.log.txt')).open('x') as stream:stream.writelines(lines)
    after=inputs(stage)
    report={'command':command,'exit_code':code,'stopped_on':abort,'seconds':round(time.monotonic()-started,3),
        'error_lines':[line.strip() for lines in output.values() for line in lines if any(x in line for x in ERRORS)],
        'source_changed_during_run':[name for name in before.keys()|after.keys() if before.get(name)!=after.get(name)]}
    save(QA/(label+'-result.json'),report);print(json.dumps(report,ensure_ascii=False),flush=True)
    if code!=0 or report['error_lines'] or report['source_changed_during_run']:raise SystemExit(1)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['font','export','build','verify']);parser.add_argument('--prefix',default='');args=parser.parse_args()
    if args.stage=='export':
        directory=tempfile.mkdtemp(prefix='godot-v061-reference-')
        env=dict(os.environ,XDG_DATA_HOME=directory+'/data',XDG_CONFIG_HOME=directory+'/config',XDG_CACHE_HOME=directory+'/cache',GODOT_SILENCE_ROOT_WARNING='1')
        run('export',args.prefix+'godot-export',['godot','--headless','--path',str(ROOT),'--script','res://tools/export_reference.gd'],env)
    elif args.stage=='font':run('font',args.prefix+'font-coverage',['python3','tools/check_font_coverage.py','--json'])
    elif args.stage=='build':
        for label,command in [('build',['python3','tools/build_reference.py']),('build-check',['python3','tools/build_reference.py','--check']),('javascript-syntax',['node','--check','docs/reference/reference.js'])]:run('build',args.prefix+label,command)
    else:run('verify',args.prefix+'focused-reference',['python3','docs/qa/v061-reference/check-reference.py'])
if __name__=='__main__':main()
