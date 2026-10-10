from pathlib import Path
import json,statistics
QA=Path(__file__).resolve().parent
def stats(values):
    a=sorted(values)
    return {'median':statistics.median(a),'p95':a[min(len(a)-1,int(len(a)*.95))],'max':max(a)} if a else {}
summary={}
for path in sorted(QA.glob('*/render.json')):
    d=json.loads(path.read_text());rows=[]
    for w in d['windows']:
        f=w['frames'];calls=[c for row in f for c in row['calls']]
        row={'label':w['label'],'mode':w['mode'],'wall_ms':stats([r['wall_us']/1000 for r in f]),'draw_signal_ms':stats([r['draw_signal_interval_us']/1000 for r in f]),'setup_cpu_ms':stats([r['frame_setup_cpu_ms'] for r in f]),'viewport_cpu_ms':stats([r['viewport_cpu_ms'] for r in f]),'viewport_gpu_ms':stats([r['viewport_gpu_ms'] for r in f]),'draw_calls':stats([r['draw_calls'] for r in f]),'overview_draw_us':stats([c[2]-c[1] for c in calls if c[0]=='overview_draw']),'overview_draw_count':sum(c[0]=='overview_draw' for c in calls),'main_frame_ms':stats([sum(c[2]-c[1] for c in r['calls'] if c[0]=='main_process')/1000 for r in f]),'cpu_delta':w['cpu_delta']}
        rows.append(row)
        print(path.parent.name,w['label'],w['mode'], 'wall',row['wall_ms'],'cpu/gpu',row['viewport_cpu_ms']['median'],row['viewport_gpu_ms']['median'],'draw_count',row['overview_draw_count'],'signal',row['draw_signal_ms']['median'])
    summary[path.parent.name]={'fixture_digest':d['fixture_digest'],'renderer':d['renderer'],'cpu_max':d['cpu_max'],'lp_num_threads':d['lp_num_threads'],'windows':rows}
(QA/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
