#!/usr/bin/env python3
"""Read retained evidence, without running Godot or rewriting its raw outputs."""
import hashlib, json, pathlib, re
QA=pathlib.Path(__file__).resolve().parent
ROOT=QA.parents[2]
def read(name): return json.loads((QA/name).read_text())
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
checks=[]
def check(ok,label):
    checks.append({'ok':bool(ok),'label':label})
    if not ok: raise AssertionError(label)
runs={}
for name in ['main','v081-zero','v082-zero']:
    run=read(name+'-run.json'); result=read(name+'-result.json')
    final=json.loads(re.search(r'^COLD_DURATION_GAMEPLAY (.+)$',(QA/(name+'.log')).read_text(),re.M).group(1))
    check(run['exit_code']==0 and not run['errors'] and result['failures']==0 and final['failures']==0,name+' success, no engine errors')
    check(run['test_sha256']==sha(ROOT/'tests/cold_ailment_duration_gameplay_test.gd'),name+' tested final script hash')
    check(final['checks']==result['checks']+1,name+' one final report-open check is logged after serializing report')
    runs[name]={'elapsed_seconds':run['elapsed_seconds'],'logged_checks':final['checks'],'report_checks':result['checks'],'failures':0}
before=QA/'v081-zero-result.combat.bin'; after=QA/'v082-zero-result.combat.bin'
check(before.read_bytes()==after.read_bytes(),'all observed combat bytes exactly match without projection')
old=read('v081-zero-result.json');new=read('v082-zero-result.json')
check(old['zero_source']==new['zero_source'],'all raw JSON combat objects exactly match')
check([old['schema'],new['schema']]==[48,49],'schema is retained separately as48→49')
compiled=read('fixtures/compiled-preview.json')
fixture_rows={}
for label,value in compiled.items():
    path=QA/'fixtures'/(label+'.json'); state=json.loads(path.read_text())
    check(state['version']==49 and state['progress']['level']==4,label+' current schema and lawful level4')
    enabled=label.startswith('after-')
    check(('14209' in state['talents']['allocated'])==enabled,label+' exact selected source state')
    check(state['talents']['normal_points']==(0 if enabled else 1),label+' eight-point budget')
    fixture_rows[label]={'file':str(path.relative_to(QA)),'sha256':sha(path),'group_id':value['group_id'],
        'mana':value['cast']['mana'],'cooldown':value['cast']['cooldown'],
        'slow':value['cast']['recipe'].get('slow'),'freeze':value['cast'].get('freeze_profile')}
record={'ok':True,'checks':len(checks),'failures':0,'runs':runs,
    'zero_source':{'comparison':'unmodified var_to_bytes of five complete cast/preview and combat-observation records',
                   'scenario_count':len(old['zero_source']),'observations_per_scenario':5,
                   'bytes_each':before.stat().st_size,'sha256':sha(before),'byte_equal':True,
                   'removed_combat_fields':[],
                   'schema_note':'48/49 and full final canonical models remain in raw JSON, outside combat-record byte stream'},
    'fixtures':fixture_rows,'checks_detail':checks}
(QA/'acceptance.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:record[k] for k in ['ok','checks','failures','runs','zero_source']},ensure_ascii=False))
