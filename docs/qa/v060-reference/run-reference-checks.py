#!/usr/bin/env python3
"""Bounded, immutable evidence for v60 references and the exact font inputs."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[3]
QA=ROOT/'docs/qa/v060-reference'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):
    with path.open('x') as stream:json.dump(value,stream,ensure_ascii=False,indent=2);stream.write('\n')
def font_inputs():
    spec=importlib.util.spec_from_file_location('coverage',ROOT/'tools/check_font_coverage.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    manifest=json.loads((ROOT/module.MANIFEST_PATH).read_text())
    return module.runtime_paths(ROOT)+[ROOT/'tools/check_font_coverage.py',ROOT/module.FONT_PATH,ROOT/module.MANIFEST_PATH,ROOT/manifest['license']['path']]
def gd_inputs():
    seen=set()
    def visit(path):
        if path in seen:return
        seen.add(path)
        if path.suffix!='.gd':return
        for relative in re.findall(r'res://([^"\n]+)',path.read_text()):
            target=ROOT/relative
            if target.is_file() and target.suffix in {'.gd','.json'}:visit(target)
    visit(ROOT/'tools/export_reference.gd')
    # Source tree runtime reads and manifest verification inputs.
    seen.update((ROOT/'data').rglob('*.json'))
    seen.add(ROOT/'project.godot')
    seen.difference_update({ROOT/'docs/reference/catalog.json',ROOT/'docs/reference/source-tree-coverage.json'})
    return list(seen)
def inputs(stage):
    if stage=='font':paths=font_inputs()
    elif stage=='export':paths=gd_inputs()
    elif stage=='build':paths=[ROOT/p for p in ['tools/build_reference.py','docs/reference/catalog.json','docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json','assets/art/equipment/forgeblade.png']]
    else:paths=[ROOT/p for p in ['docs/qa/v060-reference/check-reference.py','docs/qa/v060-reference/v059-baseline.json','docs/reference/catalog.json','docs/reference/index.html','docs/reference/source-tree-coverage.json']]
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(set(paths)) if p.is_file()}
def run(stage,label,command,env=None):
    before=inputs(stage);save(QA/(label+'-input-sha256.json'),before)
    started=time.monotonic();timed_out=False
    try:
        result=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,text=True,timeout=180)
        stdout,stderr,code=result.stdout,result.stderr,result.returncode
    except subprocess.TimeoutExpired as exc:
        timed_out=True;code=None
        stdout=exc.stdout.decode() if isinstance(exc.stdout,bytes) else (exc.stdout or '')
        stderr=exc.stderr.decode() if isinstance(exc.stderr,bytes) else (exc.stderr or '')
    for suffix,content in [('stdout',stdout),('stderr',stderr)]:
        with (QA/(label+'.'+suffix+'.log.txt')).open('x') as stream:stream.write(content)
    after=inputs(stage)
    report={'command':command,'exit_code':code,'timed_out':timed_out,'seconds':round(time.monotonic()-started,3),
            'error_lines':[line for line in (stdout+'\n'+stderr).splitlines() if any(x in line for x in ['SCRIPT ERROR','ERROR:','Assertion','Traceback','Parse Error'])],
            'source_changed_during_run':[name for name in before.keys()|after.keys() if before.get(name)!=after.get(name)]}
    save(QA/(label+'-result.json'),report);print(json.dumps(report,ensure_ascii=False),flush=True)
    if code!=0 or report['error_lines'] or report['source_changed_during_run']:raise SystemExit(1)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['font','export','build','verify']);parser.add_argument('--prefix',default='');args=parser.parse_args()
    if args.stage=='export':
        directory=tempfile.mkdtemp(prefix='godot-v060-reference-')
        env=dict(os.environ,XDG_DATA_HOME=directory+'/data',XDG_CONFIG_HOME=directory+'/config',XDG_CACHE_HOME=directory+'/cache',GODOT_SILENCE_ROOT_WARNING='1')
        run('export',args.prefix+'godot-export',['godot','--headless','--path',str(ROOT),'--script','res://tools/export_reference.gd'],env)
    elif args.stage=='font':run('font',args.prefix+'font-coverage',['python3','tools/check_font_coverage.py','--json'])
    elif args.stage=='build':
        for label,command in [('build',['python3','tools/build_reference.py']),('build-check',['python3','tools/build_reference.py','--check']),('javascript-syntax',['node','--check','docs/reference/reference.js'])]:run('build',args.prefix+label,command)
    else:run('verify',args.prefix+'focused-reference',['python3','docs/qa/v060-reference/check-reference.py'])
if __name__=='__main__':main()
