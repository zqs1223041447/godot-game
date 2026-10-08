#!/usr/bin/env python3
"""Materialize only approved non-executable glTF data; never unpack package programs."""
from pathlib import Path, PurePosixPath
import hashlib, json, os, zipfile
ROOT=Path(__file__).resolve().parents[1]
SRC=Path(os.environ['V121_SOURCE_ARCHIVES']).expanduser()
ARCHIVES={
 'fantasy': ('Modular Character Outfits - Fantasy[Standard].zip','c3468b18871cc8c8f05ab14df7712baf22cb9f389cbd870babf130e595187f70'),
 'base': ('Universal Base Characters[Standard].zip','fdbf1804c90dfc1ea03e992bff7da2dfd1a79318e13270a660180f9308455f40')}
SELECTION={
 'fantasy': ['Exports/glTF (Godot-Unreal)/Outfits/Female_Ranger.gltf','Exports/glTF (Godot-Unreal)/Modular Parts/Female_Peasant_Body.gltf'],
 'base':['Base Characters/Godot - UE/Superhero_Female_FullBody.gltf','Base Characters/Godot - UE/Superhero_Male_FullBody.gltf','Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_BuzzedFemale.gltf']}
FIXES={'T_Eye_Normal_png.png':'T_Eye_Normal.png','T_Hair_1_Normal_png.png':'T_Hair_1_Normal.png'}
report={'archives':{},'files':[],'uri_repairs':[],'asset_paths':{}}
for package,(filename,expected) in ARCHIVES.items():
 path=SRC/filename; sha=hashlib.sha256(path.read_bytes()).hexdigest(); assert sha==expected,(path,sha)
 report['archives'][package]={'filename':filename,'sha256':sha,'bytes':path.stat().st_size}
 with zipfile.ZipFile(path) as z:
  names=z.namelist(); prefix=filename[:-4]+'/'
  selected=[prefix+p for p in SELECTION[package]]
  dependencies=set(selected)
  parsed={}
  for name in selected:
   d=json.loads(z.read(name)); parsed[name]=d
   for im in d.get('images',[]):
    original=im['uri']; correct=FIXES.get(original,original)
    if original!=correct:
     assert str(PurePosixPath(name).parent/correct) in names
     im['uri']=correct
     report['uri_repairs'].append({'gltf':name,'old_uri':original,'new_uri':correct})
   for item in d.get('buffers',[])+d.get('images',[]):
    uri=item['uri']; assert not (uri.startswith(('data:','http:','https:','/')) or '..' in PurePosixPath(uri).parts)
    dependencies.add(str(PurePosixPath(name).parent/uri))
  dependencies.add(prefix+'License_Standard.txt')
  if prefix+'Readme.txt' in names:dependencies.add(prefix+'Readme.txt')
  for name in sorted(dependencies):
   assert PurePosixPath(name).suffix.lower() in ['.gltf','.bin','.png','.txt']
   raw=z.read(name); dest=ROOT/'work_sources'/name; dest.parent.mkdir(parents=True,exist_ok=True)
   output=json.dumps(parsed[name],indent=2).encode() if name in parsed else raw
   dest.write_bytes(output)
   report['files'].append({'archive':package,'entry':name,'source_sha256':hashlib.sha256(raw).hexdigest(),'working_sha256':hashlib.sha256(output).hexdigest(),'bytes':len(output)})
  for name in selected: report['asset_paths'][PurePosixPath(name).stem]=str(ROOT/'work_sources'/name)
assert len(report['uri_repairs'])==3
(ROOT/'reports/source-manifest.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'assets':report['asset_paths'],'repairs':report['uri_repairs'],'files':len(report['files'])},indent=2))
