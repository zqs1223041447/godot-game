from pathlib import Path
import hashlib,json,importlib.util,io,time
from fontTools.ttLib import TTFont
R=Path(__file__).resolve().parents[3];Q=Path(__file__).resolve().parent;B=R.parent/'v069-physical-fire-conversion';sha=lambda b:hashlib.sha256(b).hexdigest()
spec=importlib.util.spec_from_file_location('coverage',R/'tools/check_font_coverage.py');C=importlib.util.module_from_spec(spec);spec.loader.exec_module(C)
t=time.monotonic();old=json.loads((B/'docs/qa/v069-integration/font-coverage.json').read_text());proof={'font_sha256':old['font_sha256']};font=(R/'assets/fonts/arena_sans.otf').read_bytes();assert sha(font)==proof['font_sha256']
oldpaths=old['unchanged_runtime_files']|old['scanned_runtime_files'];mapped=set(TTFont(io.BytesIO(font)).getBestCmap());unchanged={};scanned={};missing={};fallbacks={};required=set()
for p in C.runtime_paths(R):
 n=p.relative_to(R).as_posix();h=sha(p.read_bytes());value={'sha256':h,'bytes':p.stat().st_size}
 if n in oldpaths and oldpaths[n]['sha256']==h:unchanged[n]=value
 else:
  scanned[n]=value
  for line,text in C.file_strings(p):
   for cp in C.printable_codepoints(text)-mapped:
    (fallbacks if cp in [0x25c8,0x2301] else missing).setdefault(cp,[]).append(n+':'+str(line))
 # Count only the unique set; avoid expensive complete per-character location lists.
 for line,text in C.file_strings(p):required.update(C.printable_codepoints(text))
manifest=json.loads((R/'assets/fonts/coverage_manifest.json').read_text())
for src in manifest['supplemental_sources']:
 for item in src['strings']:required.update(C.printable_codepoints(item['text']))
result={'base_commit':'d25717c4485bf36688df36460f2c85ebb11b7623','method':'Complete v69 coverage with same font, byte-identical files reused; changed/new runtime strings freshly scanned','font_sha256':sha(font),'runtime_files':len(unchanged)+len(scanned),'unchanged_runtime_files':unchanged,'scanned_runtime_files':scanned,'mapped':len(mapped),'missing':[{'char':chr(k),'codepoint':'U+%04X'%k,'locations':sorted(set(v))} for k,v in sorted(missing.items())],'existing_fallbacks':[{'char':chr(k),'locations':sorted(set(v))} for k,v in sorted(fallbacks.items())],'seconds':time.monotonic()-t};(Q/'font-coverage.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');(Q/'font-required-set.json').write_text(json.dumps({'count':len(required),'codepoints':sorted(required)},indent=2)+'\n');print({k:result[k] for k in ['font_sha256','runtime_files','mapped','missing','seconds']});print('required',len(required),'unchanged',len(unchanged),'fresh',len(scanned))
