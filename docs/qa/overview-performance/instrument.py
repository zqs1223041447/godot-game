"""Generate temporary instrumented copies; original function bodies stay verbatim."""
from pathlib import Path
import hashlib,json,re,subprocess,os
ROOT=Path(__file__).resolve().parents[3];OUT=Path('/tmp/godot-overview-profile-src');OUT.mkdir(exist_ok=True)
PROFILE='res://docs/qa/overview-performance/profile.gd'
files={
 'overview':('scripts/ui/exploration_map_overview.gd',{'_draw':('overview_draw','',None),'update_live':('overview_state','world, position_value, facing','Dictionary'), 'update_player':('overview_player','position_value, facing',None)}),
 'hud':('scripts/game_hud.gd',{'_refresh_world':('hud_world_refresh','',None),'_tick_overview':('overview_tick','delta',None),'_refresh_cleanup_hint':('cleanup_refresh','',None),'_process':('hud_process','delta',None)}),
 'main':('scripts/main.gd',{'world_context':('world_context','','Dictionary'),'_camp_states':('camp_scan','','Array[Dictionary]'),'_outpost_states':('outpost_scan','','Array[Dictionary]'),'exploration_cleanup_hint':('cleanup_query','','Dictionary'),'tick':('game_step','delta',None),'_process':('main_process','delta',None)})}
record={}
for name,(source,functions) in files.items():
    original=subprocess.check_output(['git','show',os.environ['OVERVIEW_PROFILE_REV']+':'+source],cwd=ROOT).decode() if os.environ.get('OVERVIEW_PROFILE_REV') else (ROOT/source).read_text();text=re.sub(r'^class_name \w+\n','',original)
    if name=='hud':text=text.replace('res://scripts/ui/exploration_map_overview.gd',str(OUT/'overview.gd'))
    if name=='main':text=text.replace('res://scripts/game_hud.gd',str(OUT/'hud.gd'))
    text+='\nconst PerfProbe=preload("'+PROFILE+'")\n'
    for function,(label,args,_) in functions.items():
        match=re.search(r'^func '+function+r'\(([^\n]*)\)([^\n]*):\n',text,re.M)
        assert match,function
        signature=match[0].rstrip('\n');renamed=signature.replace('func '+function+'(','func _profile_original_'+function+'(',1)
        text=text[:match.start()]+renamed+'\n'+text[match.end():]
        returns=match[2].strip();rtype=returns.removeprefix('->').strip()
        body=signature+'\n\tvar started:=Time.get_ticks_usec()\n'
        call='_profile_original_'+function+'('+args+')'
        if rtype and rtype!='void':body+='\tvar result:'+rtype+'='+call+'\n'
        else:body+='\t'+call+'\n'
        body+='\tvar ended:=Time.get_ticks_usec()\n\tPerfProbe.record("'+label+'",started,ended)\n'
        if rtype and rtype!='void':body+='\treturn result\n'
        text+='\n'+body
    target=OUT/(name+'.gd');target.write_text(text)
    record[source]={'sha256':hashlib.sha256(original.encode()).hexdigest(),'instrumented_sha256':hashlib.sha256(text.encode()).hexdigest(),'functions':list(functions)}
(ROOT/'docs/qa/overview-performance/instrumentation.json').write_text(json.dumps(record,indent=2)+'\n')
print(OUT)
