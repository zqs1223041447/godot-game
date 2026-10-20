#!/usr/bin/env python3
"""Reassemble only the accepted archive and extract the exact audited file set."""
import hashlib,json,stat,sys,zipfile
from pathlib import Path
root=Path(__file__).resolve().parent
out=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('release-output').resolve()
m=json.loads((root/'manifest.json').read_text())
def check(data,entry):
    if len(data)!=entry['bytes'] or hashlib.sha256(data).hexdigest()!=entry['sha256']:
        raise ValueError('Size/hash mismatch')
if out.exists():
    raise ValueError('Output must not already exist')
parts=[]
for i,entry in enumerate(m['chunks']):
    if entry['name']!=f'chunks/game.zip.part{i:03d}': raise ValueError('Invalid chunk path/order')
    data=(root/entry['name']).read_bytes(); check(data,entry); parts.append(data)
data=b''.join(parts); check(data,m['archive'])
if m['archive']['name']!='godot-game-web.zip': raise ValueError('Invalid archive filename')
out.mkdir(parents=True); archive=out/'godot-game-web.zip'; archive.write_bytes(data)
with zipfile.ZipFile(archive) as z:
    names=z.namelist()
    if len(names)!=10 or len(set(names))!=10 or set(names)!=set(m['web_files']):
        raise ValueError('Unexpected archive entries')
    for entry in z.infolist():
        if '/' in entry.filename or '\\' in entry.filename or entry.filename in ('.','..') or stat.S_ISLNK(entry.external_attr>>16):
            raise ValueError('Unsafe ZIP member')
        check(z.read(entry),m['web_files'][entry.filename])
    web=out/'web'; web.mkdir()
    for name in names: (web/name).write_bytes(z.read(name))
(web/'.nojekyll').touch()
(out/'SHA256SUMS').write_text(m['archive']['sha256']+'  godot-game-web.zip\n')
print(json.dumps({'status':'verified','archive_sha256':m['archive']['sha256'],'files':len(names),'chunks':len(parts),'web_bytes':sum(x['bytes'] for x in m['web_files'].values())}))
