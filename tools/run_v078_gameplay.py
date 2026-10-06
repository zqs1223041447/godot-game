#!/usr/bin/env python3
"""Bounded v078 Main/source gameplay and unchanged-script v077 frozen oracle.
Run only after coordinator import. This tool never imports or changes baseline.
"""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'docs/qa/v078-gameplay'
BASE='07922581e2924dbb6fbadd1fb51242ae87a16293'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def sources(root, frozen=False):
    result={}
    for entry in subprocess.check_output(['git','ls-tree','-rz',BASE],cwd=root).split(b'\0'):
        if not entry: continue
        meta,name=entry.split(b'\t',1); name=name.decode()
        if not (name.startswith(('scripts/','scenes/','data/')) or name=='project.godot'): continue
        data=(root/name).read_bytes(); blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        expected=meta.split()[2].decode()
        if frozen and blob!=expected: raise RuntimeError(f'Frozen source mismatch {name}')
        result[name]={'sha256':hashlib.sha256(data).hexdigest(),'git_blob':blob,'base_blob':expected}
    if not frozen:
        for directory in ('scripts','scenes','data'):
            for path in (root/directory).rglob('*'):
                if not path.is_file(): continue
                name=path.relative_to(root).as_posix()
                if name not in result:
                    data=path.read_bytes()
                    result[name]={'sha256':hashlib.sha256(data).hexdigest(),'git_blob':hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest(),'base_blob':None}
    return result
def execute(label,root,script,extra,godot):
    sandbox=Path(tempfile.mkdtemp(prefix='godot-m1-v078-gameplay-'))
    env=dict(os.environ,XDG_DATA_HOME=str(sandbox),XDG_CONFIG_HOME=str(sandbox/'config'),XDG_CACHE_HOME=str(sandbox/'cache'),GODOT_SILENCE_ROOT_WARNING='1',**extra)
    command=[godot,'--headless','--path',str(root),'--script',str(ROOT/'tests'/script)]
    started=time.monotonic(); log=QA/(label+'.log')
    with log.open('w') as stream:
        try: result=subprocess.run(command,cwd=root,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=60); code=result.returncode
        except subprocess.TimeoutExpired: code=124
    text=log.read_text(); outcome={'label':label,'exit':code,'seconds':round(time.monotonic()-started,3),'log':str(log.relative_to(ROOT)),'log_sha256':sha(log),'sandbox':str(sandbox),'command':command}
    (QA/(label+'-run.json')).write_text(json.dumps(outcome,indent=2)+'\n')
    print(text,flush=True)
    if code or 'SCRIPT ERROR' in text or 'ERROR:' in text: raise RuntimeError(f'Failed {label}: {outcome}')
    return outcome

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=['gameplay','legacy','all'],default='all'); parser.add_argument('--sections',default=''); parser.add_argument('--label',default='first')
    parser.add_argument('--baseline',type=Path,default=ROOT.parent/'v077-combat-outcome-feedback'); parser.add_argument('--godot',default='/usr/local/bin/godot')
    args=parser.parse_args(); QA.mkdir(parents=True,exist_ok=True); (QA/'fixtures').mkdir(exist_ok=True)
    before=sources(ROOT); manifest={'base':BASE,'current':before,'gameplay_fixture_sha256':sha(ROOT/'tests/elemental_conversion_gameplay_test.gd'),'legacy_fixture_sha256':sha(ROOT/'tests/elemental_conversion_legacy_probe.gd')}; runs=[]
    if args.mode in ('legacy','all'):
        manifest['frozen']=sources(args.baseline,True)
        if not (args.baseline/'.godot/global_script_class_cache.cfg').exists(): raise RuntimeError('Baseline existing import cache required')
    (QA/(args.label+'-sources.json')).write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    if args.mode in ('gameplay','all'):
        label=args.label+'-gameplay'
        runs.append(execute(label,ROOT,'elemental_conversion_gameplay_test.gd',{'ELEMENTAL_GAMEPLAY_REPORT':str(QA/(label+'.json')),'ELEMENTAL_GAMEPLAY_SECTIONS':args.sections,'ELEMENTAL_FIXTURE_OUTPUT':str(QA/'fixtures/selected.json'),'ELEMENTAL_FIXTURE_DIRECTORY':str(QA/'fixtures')},args.godot))
    comparison={}
    if args.mode in ('legacy','all'):
        for version,root in [('v077',args.baseline),('v078',ROOT)]:
            label=args.label+'-'+version
            runs.append(execute(label,root,'elemental_conversion_legacy_probe.gd',{'ELEMENTAL_LEGACY_OUTPUT':str(QA/label)},args.godot))
        for suffix in ['.bin','.actors.bin','.actors-without-policy-versions.bin','.save']:
            left=QA/(args.label+'-v077'+suffix); right=QA/(args.label+'-v078'+suffix)
            comparison[suffix]={'equal':left.read_bytes()==right.read_bytes(),'bytes':[left.stat().st_size,right.stat().st_size],'sha256':[sha(left),sha(right)]}
        left=json.loads((QA/(args.label+'-v077.save')).read_text()); right=json.loads((QA/(args.label+'-v078.save')).read_text())
        comparison['save_schema']=[left.pop('version'),right.pop('version')]; comparison['save_equal_except_schema']=left==right
        old=json.loads((QA/(args.label+'-v077.json')).read_text())['source_metadata']; new=json.loads((QA/(args.label+'-v078.json')).read_text())['source_metadata']
        changes=[{'path':a['path'],'v077':a['value'],'v078':b['value']} for a,b in zip(old,new) if a!=b]
        comparison['source_metadata_changes']=changes
        comparison['metadata_scope_valid']=len(old)==len(new) and all(a['path']==b['path'] and (a==b or (a['path'].endswith('/source_policy') and a['value']==45 and b['value']==48) or (a['path'].endswith('/source_save_version') and a['value']==45 and b['value']==48) or (a['path'].endswith(('/policy_version','/mechanism_policy')) and isinstance(a['value'],str) and a['value'].replace(':policy:45',':policy:48')==b['value'])) for a,b in zip(old,new))
        (QA/(args.label+'-comparison.json')).write_text(json.dumps(comparison,indent=2)+'\n')
        if not (comparison['.bin']['equal'] and comparison['.actors-without-policy-versions.bin']['equal'] and comparison['save_schema']==[47,48] and comparison['save_equal_except_schema'] and comparison['metadata_scope_valid']): raise RuntimeError('Legacy comparison differs; see retained comparison')
    after=sources(ROOT); changed={p for p in set(before)|set(after) if after.get(p)!=before.get(p)}
    if changed: raise RuntimeError(f'Production changed during acceptance: {sorted(changed)}')
    if 'frozen' in manifest and sources(args.baseline,True)!=manifest['frozen']: raise RuntimeError('Frozen baseline changed')
    (QA/(args.label+'-result.json')).write_text(json.dumps({'runs':runs,'comparison':comparison,'source_manifest':args.label+'-sources.json'},indent=2)+'\n')
if __name__=='__main__': main()
