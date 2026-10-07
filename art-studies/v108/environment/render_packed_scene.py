"""Render the already packed scene without rebuilding, downloading, or saving it.
Load the .blend with Blender --disable-autoexec, then pass -- --output /path/image.png.
"""
import argparse
from pathlib import Path
import sys
import bpy

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args(argv)
expected = (Path(__file__).resolve().parent / 'sunlit-ruins-environment.blend').resolve()
if Path(bpy.data.filepath).resolve() != expected:
    raise RuntimeError('Open the adjacent archived packed scene first')
missing = [image.name for image in bpy.data.images if image.source == 'FILE' and not image.packed_file]
if missing:
    raise RuntimeError('External image dependencies: ' + ', '.join(missing))
output = args.output.resolve()
original = expected.parent.parent / 'godot_preview' / 'assets' / 'environment-final.png'
if output == original.resolve():
    raise RuntimeError('Choose a new output path; preserve the accepted beauty image')
output.parent.mkdir(parents=True, exist_ok=True)
bpy.context.scene.render.filepath = str(output)
bpy.ops.render.render(write_still=True)
