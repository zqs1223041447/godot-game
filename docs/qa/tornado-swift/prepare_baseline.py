"""Read the three old compiler dependencies into /tmp; never revert workspace files."""
from pathlib import Path
import hashlib, json, subprocess
BASE = '9123d117995af72b87d145aa248cea198eeaa881'
ROOT = Path(__file__).resolve().parents[3]
OUT = Path('/tmp/godot-tornado-swift-baseline')
OUT.mkdir(exist_ok=True)
names = ['skill_compiler', 'support_registry', 'delivery_support_rules']
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
Path(__file__).with_name('baseline.json').write_text(json.dumps({'base': BASE, 'files': records}, indent=2) + '\n')
