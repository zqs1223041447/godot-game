"""Reuse the existing extractor, also detaching the changed GameData catalog."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[3]
BASE='18303a9b8012c28989b785c1809a03f4972641e4'
OUT=Path('/tmp/godot-nova-lingering-baseline')
REPORT=Path(__file__).with_name('baseline.json')
subprocess.run(['python3',str(ROOT/'docs/qa/tornado-swift/prepare_baseline.py'),'--base',BASE,'--out',str(OUT),'--dependency','player_trap_runtime','--report',str(REPORT)],check=True,cwd=ROOT)
report=json.loads(REPORT.read_text())
raw=subprocess.check_output(['git','show',BASE+':scripts/game_data.gd'],cwd=ROOT)
detached='\n'.join(line for line in raw.decode().splitlines() if not line.startswith('class_name '))+'\n'
(OUT/'game_data.gd').write_text(detached)
report['files']['scripts/game_data.gd']={'original_sha256':hashlib.sha256(raw).hexdigest(),'detached_sha256':hashlib.sha256(detached.encode()).hexdigest()}
for source,record in report['files'].items():
    path=OUT/Path(source).name
    path.write_text(path.read_text().replace('res://scripts/game_data.gd',str(OUT/'game_data.gd')))
    record['detached_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
REPORT.write_text(json.dumps(report,indent=2)+'\n')
