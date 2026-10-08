"""Read-only verification of the finite authored export archive; no rendering."""
import ast
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'MANIFEST.json').read_text())
for row in manifest['files']:
    path = ROOT / row['path']
    assert path.is_file() and not path.is_symlink(), row['path']
    assert path.stat().st_size == row['bytes'], row['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row['sha256'], row['path']
frames = json.loads((ROOT / 'reports/source-frame-hashes.json').read_text())['frames']
assert len(frames) == 16
assert sorted(p.name for p in (ROOT / 'frames/candidate').glob('*.png')) == [f'{i:02d}.png' for i in range(16)]
for row in frames:
    path = ROOT / row['path']
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == row['sha256'] == row['source_v125_sha256'], row['path']
    with Image.open(path) as im:
        assert im.size == (128, 192) and im.mode == 'RGBA', row['path']
        im.load()
        assert im.getchannel('A').getextrema()[0] == 0, row['path']
meta = json.loads((ROOT / 'reports/trial-metadata.json').read_text())
assert list(meta['variants']) == ['candidate']
assert meta['variants']['candidate']['phases'] == [i/16 for i in range(16)]
assert meta['blend']['jog_weight'] == .2 and meta['blend']['walk_weight'] == .8
assert (ROOT / '.gdignore').is_file()
assert len(json.loads((ROOT / 'reports/contact-samples.json').read_text())) == 97
for path in (ROOT / 'scripts').glob('*.py'):
    ast.parse(path.read_text(), filename=path.name)
for path in (ROOT / 'licenses').glob('*.txt'):
    assert 'CC0 1.0 Universal' in path.read_text()
for path in ROOT.rglob('*'):
    assert not path.is_symlink(), str(path)
    if path.is_file():
        assert path.suffix.lower() not in {'.blend', '.blend1', '.zip', '.glb', '.fbx', '.log', '.pyc'}, str(path)
        assert '__pycache__' not in path.parts, str(path)
print('PASS: 16 byte-identical RGBA frames; metadata, 97 samples, licenses, Python syntax, .gdignore and file hashes verified. No render or runtime test performed.')
