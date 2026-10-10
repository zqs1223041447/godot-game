from pathlib import Path
import json,statistics
QA=Path(__file__).resolve().parent
KEYS=['world_context','camp_scan','outpost_scan','cleanup_query','cleanup_refresh','hud_world_refresh','overview_state','overview_player','overview_tick','overview_draw','hud_process','game_step','main_process']
def stats(values):
    if not values:return {'count':0}
    a=sorted(values)
    return {'count':len(a),'median_us':statistics.median(a),'p95_us':a[min(len(a)-1,int(len(a)*.95))],'mean_us':statistics.mean(a),'max_us':max(a)}
output={}
for path in sorted(QA.glob('*/profile.json')):
    data=json.loads(path.read_text());windows=[]
    for w in data['windows']:
        calls=[c for f in w['frames'] for c in f['calls']]
        row={'label':w['label'],'open':w['open'],'wall':stats([f['wall_us'] for f in w['frames']]),'functions':{k:stats([c[2]-c[1] for c in calls if c[0]==k]) for k in KEYS},'per_frame_sum':{k:stats([sum(c[2]-c[1] for c in f['calls'] if c[0]==k) for f in w['frames']]) for k in KEYS}}
        windows.append(row)
        print(path.parent.name,w['label'],'open',w['open'],'wall_ms',round(row['wall']['median_us']/1000,2),'main_ms',round(row['per_frame_sum']['main_process'].get('median_us',0)/1000,2),'overview_draw_ms',round(row['per_frame_sum']['overview_draw'].get('median_us',0)/1000,3),'context_calls',row['functions']['world_context']['count'])
    direct=[c for sample in data['direct'] for c in sample]
    output[path.parent.name]={'checks':data['checks'],'failures':data['failures'],'windows':windows,'direct':{k:stats([c[2]-c[1] for c in direct if c[0]==k]) for k in KEYS},'observer':stats(data['observer_calibration_us'])}
(QA/'summary.json').write_text(json.dumps(output,indent=2)+'\n')
