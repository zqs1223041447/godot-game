"""Read the three old compiler dependencies into /tmp; never revert workspace files."""
from pathlib import Path
import argparse, hashlib, json, subprocess
parser = argparse.ArgumentParser()
parser.add_argument('--base', default='9123d117995af72b87d145aa248cea198eeaa881')
parser.add_argument('--out', type=Path, default=Path('/tmp/godot-tornado-swift-baseline'))
parser.add_argument('--report', type=Path, default=Path(__file__).with_name('baseline.json'))
parser.add_argument('--dependency', action='append', default=[])
args = parser.parse_args()
BASE = args.base
ROOT = Path(__file__).resolve().parents[3]
OUT = args.out
OUT.mkdir(exist_ok=True)
names = list(dict.fromkeys(['skill_compiler', 'support_registry', 'delivery_support_rules'] + args.dependency))
records = {}
for name in names:
    source = f'scripts/combat/{name}.gd'
    raw = subprocess.check_output(['git', 'show', BASE + ':' + source], cwd=ROOT)
    text = '\n'.join(line for line in raw.decode().splitlines() if not line.startswith('class_name ')) + '\n'
    for dependency in names:
        text = text.replace(f'res://scripts/combat/{dependency}.gd', str(OUT / (dependency + '.gd')))
    (OUT / (name + '.gd')).write_text(text)
    records[source] = {'original_sha256': hashlib.sha256(raw).hexdigest(),
                       'detached_sha256': hashlib.sha256(text.encode()).hexdigest()}
args.report.write_text(json.dumps({'base': BASE, 'files': records}, indent=2) + '\n')
