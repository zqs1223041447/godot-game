#!/usr/bin/env python3
"""Freeze the bounded dependency inputs and execute the small exporter once."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
ROOT=Path(__file__).resolve().parents[3]
QA=Path(__file__).resolve().parent

def digest(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()

def main():
    target=QA/'long-stride-fragment.json'
    assert not target.exists() and not (QA/'export-run.json').exists(), 'One export only; retain prior evidence'
    pending=['tools/long_stride_reference.gd']; visited=set()
    while pending:
        path=pending.pop()
        if path in visited or not (ROOT/path).is_file():continue
        visited.add(path)
        if Path(path).suffix not in ['.gd','.tscn','.tres']:continue
        for entry in re.findall(r'res://([^"\n]+)',(ROOT/path).read_text()):
            if (ROOT/entry).is_file():pending.append(entry)
    visited.update(['project.godot','docs/LONG_STRIDE.zh-CN.md','docs/qa/v098-runtime/owned-fixture-after-runtime.json','docs/qa/v098-runtime/main3-result.json','docs/qa/v098-runtime/main3.log','docs/qa/v098-runtime/reuse-fixture.json','docs/qa/v098-runtime/tested-inputs.json','assets/ui/grimoire/long_stride.png'])
    fingerprints={p:digest(p) for p in sorted(visited)}
    (QA/'export-input-sha256.json').write_text(json.dumps(fingerprints,ensure_ascii=False,indent=2)+'\n')
    env=dict(os.environ); isolated=Path(tempfile.mkdtemp(prefix='godot-v098-reference-'))
    for key,child in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        folder=isolated/child; folder.mkdir(); env[key]=str(folder)
    command=['godot','--headless','--path',str(ROOT),'--script','res://tools/long_stride_reference.gd']
    start=time.monotonic()
    try:
        result=subprocess.run(command,cwd=ROOT,env=env,text=True,capture_output=True,timeout=50)
        stdout,stderr,code=result.stdout,result.stderr,result.returncode
    except subprocess.TimeoutExpired as error:
        stdout,stderr,code=error.stdout or b'',error.stderr or b'',124
        if isinstance(stdout,bytes):stdout=stdout.decode(errors='replace')
        if isinstance(stderr,bytes):stderr=stderr.decode(errors='replace')
    elapsed=time.monotonic()-start
    (QA/'export.stdout.log').write_text(stdout);(QA/'export.stderr.log').write_text(stderr)
    record={'command':command,'isolated_user_data':env['XDG_DATA_HOME'],'elapsed_seconds':elapsed,'exit_code':code,'export_count':int(target.exists()),'input_count':len(fingerprints),'input_fingerprints_unchanged':all(digest(p)==v for p,v in fingerprints.items()),'scope':'One bounded reference export; no Main, old exporter, combat matrix, maps, save, coverage or art generation.'}
    (QA/'export-run.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(record,ensure_ascii=False,indent=2));print(stdout);print(stderr)
    assert code==0 and target.exists() and record['input_fingerprints_unchanged'] and 'ERROR' not in stdout+stderr

if __name__=='__main__':main()
