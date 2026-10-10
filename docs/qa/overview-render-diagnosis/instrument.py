"""Extend prior timer harness in /tmp only; ablations never enter production."""
from pathlib import Path
import subprocess,sys,json,hashlib
ROOT=Path(__file__).resolve().parents[3];OUT=Path('/tmp/godot-overview-profile-src');QA=Path(__file__).resolve().parent
old=(ROOT/'docs/qa/overview-performance/instrumentation.json').read_bytes()
try:
    subprocess.run([sys.executable,str(ROOT/'docs/qa/overview-performance/instrument.py')],check=True)
    manifest=json.loads((ROOT/'docs/qa/overview-performance/instrumentation.json').read_text())
finally:
    (ROOT/'docs/qa/overview-performance/instrumentation.json').write_bytes(old)
p=OUT/'overview.gd';source=p.read_text()
source=source.replace('queue_redraw()','_probe_redraw()')
source+='\nfunc _probe_redraw()->void:\n\tif not get_meta("probe_retain",false):queue_redraw()\n'
needle='func _text(at: Vector2, value: String, color: Color = INK, font_size: int = 13) -> void:\n'
assert needle in source
source=source.replace(needle,needle+'\tif get_meta("probe_no_text",false):return\n')
needle='func _profile_original__draw() -> void:\n'
assert needle in source
source=source.replace(needle,needle+'\tif get_meta("probe_empty",false):return\n')
p.write_text(source)
manifest['scripts/ui/exploration_map_overview.gd']['diagnostic_sha256']=hashlib.sha256(source.encode()).hexdigest()
(QA/'instrumentation.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Temporary retain/no-text/empty diagnostics generated')
