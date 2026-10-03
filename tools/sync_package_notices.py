#!/usr/bin/env python3
"""Copy every renamed package notice from the exact frozen source manifest.

No inherited release archive may supply authoritative current asset/font notices.
Run before zipping; --check verifies an already assembled package without writes.
"""
from pathlib import Path
import argparse
import hashlib
import json

NOTICES = {
    'assets/ui/grimoire/asset_manifest.json': 'asset-notices/grimoire-manifest.json',
    'assets/art/equipment/manifest.json': 'asset-notices/equipment-manifest.json',
    'assets/fonts/coverage_manifest.json': 'asset-notices/font-coverage-manifest.json',
}

def synchronize(source, source_manifest, package, check_only=False):
    manifest=json.loads(source_manifest.read_text())
    records=[]
    for original,renamed in NOTICES.items():
        data=(source/original).read_bytes()
        digest=hashlib.sha256(data).hexdigest()
        expected=manifest['files'][original]
        if len(data)!=expected['bytes'] or digest!=expected['sha256']:
            raise ValueError('Frozen notice differs from source manifest: '+original)
        target=package/renamed
        if not check_only:
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(data)
        if target.read_bytes()!=data:
            raise ValueError('Package notice differs from frozen source: '+renamed)
        records.append({'source':original,'package':renamed,'sha256':digest,'bytes':len(data)})
    return {'source_commit':manifest['commit'],'notices':records,'all_match':True}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('source_manifest',type=Path)
    parser.add_argument('package',type=Path)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    print(json.dumps(synchronize(args.source,args.source_manifest,args.package,args.check),indent=2))
