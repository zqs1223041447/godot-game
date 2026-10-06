from pathlib import Path
import hashlib,importlib.util,io,json,subprocess,time
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont
R=Path(__file__).resolve().parents[3];Q=R/'docs/qa/v062-integration';B='d884caea7a2260f4535ba4da2d7e005e6df006d4';F='assets/fonts/arena_sans.otf';M='assets/fonts/coverage_manifest.json'
def sha(b):return hashlib.sha256(b).hexdigest()
def old(p):return subprocess.check_output(['git','show',B+':'+p],cwd=R)
t=time.monotonic();scan=json.loads((R/'docs/qa/v062-reference/font-cmap-result.json').read_text());inputs=json.loads((R/'docs/qa/v062-reference/font-runtime-input-sha256.json').read_text())
assert scan['missing']==[{'codepoint':'U+9769','character':'革','locations':['scripts/items/defense_rating_affix_profile.gd:11']}]
spec=importlib.util.spec_from_file_location('coverage',R/'tools/check_font_coverage.py');C=importlib.util.module_from_spec(spec);spec.loader.exec_module(C)
actual={str(p.relative_to(R)) for p in C.runtime_paths(R)};assert len(actual)==177==scan['runtime_files']
assert actual<=set(inputs) and all(sha((R/p).read_bytes())==inputs[p] for p in actual)
changed=[p for p,h in inputs.items() if sha((R/p).read_bytes())!=h];assert set(changed)=={F,M},changed
manifest=json.loads((R/M).read_text());old_manifest=json.loads(old(M));expected=old_manifest.copy();expected['generation']=manifest['generation'];assert manifest==expected
assert sha((R/manifest['license']['path']).read_bytes())==manifest['license']['sha256']
with TTFont(io.BytesIO(old(F))) as previous,TTFont(R/F) as current:
 old_map=previous.getBestCmap();new_map=current.getBestCmap();assert len(old_map)==1656 and len(new_map)==1657 and set(new_map)-set(old_map)=={0x9769}
 old_fp=C.glyph_fingerprint(previous,set(old_map));new_fp=C.glyph_fingerprint(current,set(old_map));assert old_fp==new_fp
 assert C.layout_metrics(previous)==C.layout_metrics(current)==manifest['baseline']['layout_metrics']
 assert current['name'].getDebugName(1)==previous['name'].getDebugName(1)=='Arena Sans SC'
 glyphs=current.getGlyphSet();pen=DecomposingRecordingPen(glyphs);glyphs[new_map[0x9769]].draw(pen);assert any(op in ['lineTo','curveTo','qCurveTo'] for op,_ in pen.value)
report={'passed':True,'mode':'Fresh177-file cmap discovery plus unchanged input SHA and exact old-glyph proof; no repeated full scanner','base_commit':B,'added_codepoints':['U+9769'],'added_character':'革','runtime_inputs_unchanged':177,'required_codepoints':scan['required_codepoints'],'required_han':scan['required_han'],'mapped_codepoints':1657,'old_mapped_codepoints':1656,'missing':[],'fallback_symbols':scan['fallback_symbols'],'old_font_sha256':sha(old(F)),'font_sha256':sha((R/F).read_bytes()),'font_bytes':(R/F).stat().st_size,'old_glyph_fingerprint':old_fp,'new_old_glyph_fingerprint':new_fp,'old_outlines_advances_layout_family_license_preserved':True,'seconds':time.monotonic()-t}
(Q/'font-addition-preservation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
