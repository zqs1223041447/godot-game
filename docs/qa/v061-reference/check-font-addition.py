#!/usr/bin/env python3
"""Reconcile the one missing Han glyph without rescanning unchanged runtime text.

The preserved full scan proves every required codepoint is in old cmap, the
existing fallback set, or {U+62EC}. Exact input hashes plus retaining every old
glyph and adding that one codepoint prove current coverage without repeating
unrelated source parsing. Fingerprints compare actual old/new outlines/advances.
"""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont

ROOT=Path(__file__).resolve().parents[3]
QA=ROOT/'docs/qa/v061-reference'
BASE='b389993ed7f7a90f4043c668704583d44b22f343'
FONT='assets/fonts/arena_sans.otf'
MANIFEST='assets/fonts/coverage_manifest.json'
NEW_CP=0x62EC

def sha(raw):return hashlib.sha256(raw).hexdigest()
def load(path):return json.loads(path.read_text())
def git(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def main():
    receipt=load(QA/'font-coverage-result.json')
    scan=load(QA/'font-coverage.stdout.log.txt')
    inputs=load(QA/'font-coverage-input-sha256.json')
    baseline=load(QA/'v060-baseline.json')
    assert receipt['exit_code']==1 and not receipt['error_lines'] and not receipt['source_changed_during_run']
    assert scan['missing']==[NEW_CP] and scan['mapped_codepoints']==1655
    assert not scan['lost_baseline'] and not scan['empty_han'] and not scan['errors']
    assert scan['missing_locations']=={'U+62EC':['scripts/combat/damage_preview.gd:47']}
    current_inputs={p:sha((ROOT/p).read_bytes()) for p in inputs}
    changes=[p for p in inputs if inputs[p]!=current_inputs[p]]
    assert set(changes)=={FONT,MANIFEST},changes
    spec=importlib.util.spec_from_file_location('coverage',ROOT/'tools/check_font_coverage.py')
    coverage=importlib.util.module_from_spec(spec);spec.loader.exec_module(coverage)
    actual_paths={p.relative_to(ROOT).as_posix() for p in coverage.runtime_paths(ROOT)}
    assert len(actual_paths)==scan['runtime_files']==175
    assert actual_paths<={p for p in inputs} and all(current_inputs[p]==inputs[p] for p in actual_paths)
    old_bytes=git(FONT);old_manifest=json.loads(git(MANIFEST));manifest=load(ROOT/MANIFEST)
    assert sha(old_bytes)==inputs[FONT]==baseline['font'][FONT]
    assert sha(git(MANIFEST))==inputs[MANIFEST]==baseline['font'][MANIFEST]
    expected=old_manifest.copy();expected['generation']=manifest['generation'];assert manifest==expected
    assert sha((ROOT/manifest['license']['path']).read_bytes())==manifest['license']['sha256']
    with TTFont(io.BytesIO(old_bytes)) as old,TTFont(ROOT/FONT) as new:
        old_cmap=old.getBestCmap();new_cmap=new.getBestCmap()
        old_mapped={cp for cp,name in old_cmap.items() if name!='.notdef' and old.getGlyphID(name)!=0}
        new_mapped={cp for cp,name in new_cmap.items() if name!='.notdef' and new.getGlyphID(name)!=0}
        assert len(old_mapped)==1655 and new_mapped-old_mapped=={NEW_CP} and old_mapped<=new_mapped
        old_fingerprint=coverage.glyph_fingerprint(old,old_mapped)
        new_fingerprint=coverage.glyph_fingerprint(new,old_mapped)
        assert old_fingerprint==new_fingerprint
        assert coverage.layout_metrics(old)==coverage.layout_metrics(new)==manifest['baseline']['layout_metrics']
        assert new['name'].getDebugName(1)==old['name'].getDebugName(1)=='Arena Sans SC'
        assert new['name'].getDebugName(6)==old['name'].getDebugName(6)=='ArenaSansSC-Regular'
        glyphs=new.getGlyphSet();pen=DecomposingRecordingPen(glyphs);glyphs[new_cmap[NEW_CP]].draw(pen)
        assert any(op in ['lineTo','curveTo','qCurveTo'] for op,_ in pen.value)
    final=dict(scan,ok=True,mapped_codepoints=1656,missing=[],missing_locations={})
    report={'passed':True,'mode':'Preserved full runtime scan plus unchanged text hashes and affected font comparison',
        'initial_full_scan':'font-coverage.stdout.log.txt','initial_receipt':'font-coverage-result.json',
        'runtime_files_unchanged':len(actual_paths),'unrelated_source_rescan_performed':False,'only_changed_inputs':changes,
        'added_codepoints':['U+62EC'],'added_character':'括','all_old_1655_glyphs_and_advances_preserved':True,
        'old_glyphs_sha256':old_fingerprint,'new_old_glyphs_sha256':new_fingerprint,
        'layout_family_license_preserved':True,'old_font_sha256':sha(old_bytes),'new_font_sha256':sha((ROOT/FONT).read_bytes()),
        'old_manifest_sha256':inputs[MANIFEST],'new_manifest_sha256':current_inputs[MANIFEST],'final_coverage':final}
    with (QA/'font-addition-preservation.json').open('x') as stream:json.dump(report,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
