"""Deterministic technical assembly of existing Blender renders; no new art.

The source images remain pixel-aligned, unrotated, and unscaled. This script
only normalizes neutral shadow exports and alpha-composites the actual PNGs.
"""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from osgeo import ogr

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "exports/manifest.json"
RAW = ROOT / "source/raw-shadow-renders"
RAW.mkdir(exist_ok=True)
manifest = json.loads(MANIFEST.read_text())
collisions = json.loads((ROOT / "exports/collisions.json").read_text())
PX = manifest["projection"]["source_pixel_per_ground_m_x"]
PY = manifest["projection"]["source_pixel_per_ground_m_y"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def geom(points):
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for x, y in points + points[:1]:
        ring.AddPoint_2D(x, y)
    out = ogr.Geometry(ogr.wkbPolygon)
    out.AddGeometry(ring)
    return out


# Preserve exact original outputs. Always regenerate from originals so reruns
# cannot accumulate alpha loss. The crop and physical foot do not change.
shadow_checks = []
for module in manifest["modules"]:
    record = module["shadow"]
    path = ROOT / record["image"]
    original = RAW / path.name
    if not original.exists():
        shutil.copyfile(path, original)
    pixels = np.asarray(Image.open(original).convert("RGBA")).copy()
    alpha = pixels[:, :, 3].astype(np.float64)
    edge = np.concatenate((alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]))
    # Remove bounded shadow-catcher haze, including every crop-border pixel.
    # This is an explicit decal approximation, not a physically exact relight.
    floor = int(edge.max()) + 1
    assert floor <= 18, "Unexpected edge contamination; inspect instead of hiding it"
    cleaned = np.rint(np.maximum(0, alpha - floor) * (255.0 / (255 - floor)))
    pixels[:, :, :3] = 0
    pixels[:, :, 3] = cleaned.astype(np.uint8)
    Image.fromarray(pixels, "RGBA").save(path)
    record["method"] = (
        "Cycles native simple shadow catcher; target module only; followed by "
        "deterministic PNG RGB=0 and alpha=max(0,(a-floor)/(255-floor)); "
        "flat-ground neutral decal approximation"
    )
    record["postprocess"] = {
        "script": "source/prepare_sample.py",
        "original_render": str(original.relative_to(ROOT)),
        "original_render_sha256": digest(original),
        "png_alpha_floor_8bit": floor,
        "formula_8bit": f"round(max(0, a-{floor})*255/{255-floor})",
        "rgb_exactly_zero": True,
        "transparent_crop_border": True,
        "limitation": "Weak broad penumbra below the floor is intentionally discarded",
    }
    shadow_checks.append({"id": module["id"], "raw_edge_alpha_max": int(edge.max()),
                          "removed_alpha_floor": floor, "output_sha256": digest(path)})

MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")

layout = {
    "schema": "three-module-translation-only-assembly-v1",
    "viewport": [1280, 720],
    "screen_origin": [640, 360],
    "runtime_space": "source pixels; 1 source px = 1 Godot unit; no Camera2D zoom",
    "runtime_collision_array": "foot_relative_screen_pixel",
    "background": "qa/assembly-ground.png",
    "instances": [
        {"id": "wall_A", "module": "short_wall", "ground_xy_metres": [-3.6, 2.65]},
        {"id": "gate_A", "module": "walkable_arch", "ground_xy_metres": [1.65, 2.0]},
        {"id": "rock_A", "module": "moss_rock", "ground_xy_metres": [-4.8, -4.7]},
    ],
    "render_order": ["ground", "all_shadows", "all_ground_details", "foot_y_sorted_sprites"],
    "claim": "Technical composite of the real exported renders, not a Godot screenshot",
}
by_id = {m["id"]: m for m in manifest["modules"]}
by_collision = {m["module_id"]: m for m in collisions["modules"]}
for inst in layout["instances"]:
    x, y = inst["ground_xy_metres"]
    inst["foot_screen_pixel_exact"] = [640 + PX*x, 360 - PY*y]
    # One shared rounded foot prevents per-layer fractional-raster differences.
    inst["foot_screen_pixel"] = [round(640 + PX*x), round(360 - PY*y)]
    inst["maximum_foot_rounding_error_pixel"] = max(abs(a-b) for a,b in zip(
        inst["foot_screen_pixel"], inst["foot_screen_pixel_exact"]))
    inst["probe_points_screen_pixel"] = []
    for poly in by_collision[inst["module"]]["polygons"]:
        pt = geom(poly["outer"]["foot_relative_screen_pixel"]).PointOnSurface()
        inst["probe_points_screen_pixel"].append([
            inst["foot_screen_pixel"][0] + pt.GetX(),
            inst["foot_screen_pixel"][1] + pt.GetY()])
(ROOT / "exports/assembly-layout.json").write_text(json.dumps(layout, indent=2) + "\n")


def blit(canvas, record, foot):
    im = Image.open(ROOT / record["image"]).convert("RGBA")
    offset = record["foot_local_pixel"]
    at = (round(foot[0]-offset[0]), round(foot[1]-offset[1]))
    canvas.alpha_composite(im, at)


def assemble(background):
    canvas = background.convert("RGBA")
    for layer in ("shadow", "ground_detail", "sprite"):
        instances = layout["instances"]
        if layer == "sprite":
            instances = sorted(instances, key=lambda i: i["foot_screen_pixel"][1])
        for inst in instances:
            module = by_id[inst["module"]]
            if layer in module:
                blit(canvas, module[layer], inst["foot_screen_pixel"])
    return canvas


ground = Image.open(ROOT / layout["background"])
assembled = assemble(ground)
assembled.save(ROOT / "qa/assembly.png")
# Same exact pixels and same three placements on a second untextured receiver.
assemble(Image.new("RGBA", ground.size, (207, 214, 203, 255))).save(
    ROOT / "qa/assembly-neutral-ground.png")

font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12)
overlay = Image.new("RGBA", assembled.size)
d = ImageDraw.Draw(overlay)
colors = {"short_wall": (255, 188, 78, 255), "walkable_arch": (79, 220, 244, 255),
          "moss_rock": (238, 143, 250, 255)}
for inst in layout["instances"]:
    fx, fy = inst["foot_screen_pixel"]
    color = colors[inst["module"]]
    for poly in by_collision[inst["module"]]["polygons"]:
        pts = [(fx+x, fy+y) for x,y in poly["outer"]["foot_relative_screen_pixel"]]
        d.polygon(pts, fill=(*color[:3], 55), outline=color, width=2)
    d.line((fx-8, fy, fx+8, fy), fill="white", width=2)
    d.line((fx, fy-8, fx, fy+8), fill="white", width=2)
    d.text((fx+10, fy+7), inst["id"] + " | shared foot", font=small,
           fill="white", stroke_width=2, stroke_fill=(25,30,25,255))
gate = next(i for i in layout["instances"] if i["module"] == "walkable_arch")
line = collisions["portal_validation"]["verified_centerline"]
start, end = [[a+b for a,b in zip(gate["foot_screen_pixel"], line[k]["foot_relative_screen_pixel"])]
              for k in ("start", "end")]
d.line(start+end, fill=(145,255,125,255), width=3)
for point in (start, end):
    x,y=point
    d.ellipse((x-.3*PX,y-.3*PY,x+.3*PX,y+.3*PY), outline=(145,255,125,255), width=2)
d.rectangle((20, 20, 690, 91), fill=(18,25,22,225))
d.text((32,29), "3 REAL MODULES / translation-only assembly check", font=font, fill="white")
d.text((32,53), "Cyan: two gate legs   Green: r=0.30 m passage sweep   +: common foot", font=small, fill="white")
d.text((32,71), "55 deg orthographic / fixed sunlight / flat receiver / technical composite", font=small, fill="white")
Image.alpha_composite(assembled, overlay).save(ROOT / "qa/assembly-collision-check.png")

# Per-module real exports on a checker. Shadows intentionally sit on the ground
# before the sill and aboveground sprite; no synthetic lighting is painted here.
sheet = Image.new("RGBA", (1920, 520), (34, 40, 37, 255))
for index, module in enumerate(manifest["modules"]):
    left = index * 640
    cell = Image.new("RGBA", (640, 470))
    draw = ImageDraw.Draw(cell)
    for y in range(0, 470, 20):
        for x in range(0, 640, 20):
            shade = 196 if (x//20 + y//20) % 2 else 223
            draw.rectangle((x,y,x+19,y+19), fill=(shade,shade,shade,255))
    foot = (220,335)
    for layer in ("shadow", "ground_detail", "sprite"):
        if layer in module:
            blit(cell,module[layer],foot)
    # White anchor marker lives on QA only, never in production sprites.
    draw = ImageDraw.Draw(cell)
    draw.line((212,335,228,335),fill=(190,38,38,255),width=2)
    draw.line((220,327,220,343),fill=(190,38,38,255),width=2)
    sheet.alpha_composite(cell,(left,50))
    ImageDraw.Draw(sheet).text((left+18,17), module["id"]+" / same physical foot",font=font,fill="white")
sheet.save(ROOT / "qa/module-contact-sheet.png")

checks = {"result": "PASS", "method": "Existing Blender PNGs, deterministic technical alpha compositing",
          "new_asset_downloads": False, "blender_rerendered": False,
          "native_gameplay_screenshot": False, "shadow_normalization": shadow_checks,
          "export_checks": []}
for module in manifest["modules"]:
    for layer in ("sprite", "shadow", "ground_detail"):
        if layer not in module:
            continue
        rec=module[layer]; path=ROOT/rec["image"]
        im=Image.open(path); a=np.asarray(im)
        assert im.mode == "RGBA"
        rect=rec["source_pixel_rect"]
        assert list(im.size) == [rect["width"],rect["height"]]
        assert rec["foot_local_pixel"] == [640-rect["x"],360-rect["y"]]
        assert a[:,:,3].min()==0 and a[:,:,3].max()>0
        edges=np.concatenate((a[0,:,3],a[-1,:,3],a[:,0,3],a[:,-1,3]))
        assert edges.max()==0
        if layer=="shadow":
            assert a[:,:,:3].max()==0
        checks["export_checks"].append({"module":module["id"],"layer":layer,
            "rgba":True,"size":list(im.size),"common_source_foot":[640,360],
            "transparent_border":True,"sha256":digest(path)})
assert len(checks["export_checks"]) == 7
checks["source_module_blend_unchanged"] = digest(ROOT/"source/modules.blend")==collisions["source_module_blend_sha256"]
assert checks["source_module_blend_unchanged"]
(ROOT/"qa/export-verification.json").write_text(json.dumps(checks,indent=2)+"\n")
print("EXPORT_AND_COMPOSITE_CHECKS_PASS: 3 modules, 7 RGBA exports, shared feet, zero RGB shadows")
