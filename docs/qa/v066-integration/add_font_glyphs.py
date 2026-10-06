from pathlib import Path
import json,io,hashlib,importlib.util,time
from fontTools import subset
from fontTools.ttLib import TTFont
import fontTools
R=Path(__file__).resolve().parents[3];Q=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('coverage',R/'tools/check_font_coverage.py');C=importlib.util.module_from_spec(spec);spec.loader.exec_module(C)
sha=lambda b:hashlib.sha256(b).hexdigest()
def main():
 t=time.monotonic();F=R/'assets/fonts/arena_sans.otf';M=R/'assets/fonts/coverage_manifest.json';manifest=json.loads(M.read_text());scan=json.loads((Q/'font-coverage.json').read_text())
 for group in ['unchanged_runtime_files','scanned_runtime_files']:
  for p,v in scan[group].items():assert sha((R/p).read_bytes())==v['sha256'],p
 added=set(map(ord,'伏脚'));assert {int(x['codepoint'][2:],16) for x in scan['missing']}==added
 before=F.read_bytes();source=Path(manifest['source']['path_hint']).read_bytes();assert sha(source)==manifest['source']['sha256'];assert sha((R/manifest['license']['path']).read_bytes())==manifest['license']['sha256']
 with TTFont(io.BytesIO(before)) as old,TTFont(io.BytesIO(source),fontNumber=manifest['source']['font_number'],recalcTimestamp=False) as font:
  retained=set(old.getBestCmap());assert len(retained)==1657 and not retained&added
  assert font['name'].getDebugName(3)==manifest['source']['version'];assert C.layout_metrics(old)==C.layout_metrics(font)==manifest['baseline']['layout_metrics']
  fingerprint=C.glyph_fingerprint(old,retained);assert fingerprint==C.glyph_fingerprint(font,retained)
  requested=retained|added;assert requested<=set(font.getBestCmap());options=subset.Options();options.name_IDs=['*'];options.name_legacy=True;options.name_languages=['*'];worker=subset.Subsetter(options=options);worker.populate(unicodes=requested);worker.subset(font)
  for record in font['name'].names:
   if record.nameID in (1,4,6,16):record.string=('ArenaSansSC-Regular' if record.nameID==6 else 'Arena Sans SC').encode(record.getEncoding(),errors='replace')
  font['head'].created=manifest['baseline']['head_created'];font['head'].modified=manifest['baseline']['head_modified'];buffer=io.BytesIO();font.save(buffer);data=buffer.getvalue()
 with TTFont(io.BytesIO(data)) as new:
  assert set(new.getBestCmap())==requested and C.glyph_fingerprint(new,retained)==fingerprint
  assert C.layout_metrics(new)==manifest['baseline']['layout_metrics'] and new['name'].getDebugName(1)=='Arena Sans SC'
 baseline=set(map(ord,manifest['baseline']['characters']));generation=dict(manifest['generation']);generation.update({'fonttools_version':fontTools.__version__,'source_sha256':sha(source),'font_sha256':sha(data),'font_bytes':len(data),'mapped_codepoints':len(requested),'runtime_files':scan['runtime_files'],'added_since_baseline':''.join(map(chr,sorted(requested-baseline))),'baseline_glyphs_unchanged':True,'coverage_evidence':'docs/qa/v066-integration/font-final.json','incremental_missing_added':'伏脚'})
 # Current required count changes only by these two new characters; all other
 # old/new runtime characters were checked against the original cmap above.
 generation['required_codepoints']=int(manifest['generation']['required_codepoints'])+len(added);generation['required_han']=int(manifest['generation']['required_han'])+len(added)
 manifest['generation']=generation;F.write_bytes(data);M.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 report={'ok':True,'before_sha256':sha(before),'font_sha256':sha(data),'font_bytes':len(data),'old_codepoints':len(retained),'mapped_codepoints':len(requested),'added':['U+4F0F','U+811A'],'missing':[],'glyph_fingerprint_old':fingerprint,'glyph_fingerprint_preserved':fingerprint,'old_outlines_advances_layout_family_license_preserved':True,'source_sha256':sha(source),'runtime_files':scan['runtime_files'],'coverage_method':scan['method'],'seconds':time.monotonic()-t};(Q/'font-final.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
main()
