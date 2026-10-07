"""Verify and technically assemble real renders. No new rendering or painting."""
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from osgeo import ogr

ROOT=Path(__file__).resolve().parent.parent
OLD=ROOT.parent/'v111-modular-environment'
doc=json.loads((ROOT/'exports/manifest.rendered.json').read_text())
old_doc=json.loads((OLD/'exports/manifest.json').read_text())
old_layout=json.loads((OLD/'exports/assembly-layout.json').read_text())
old_collisions=json.loads((OLD/'exports/collisions.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(OLD/'exports/manifest.json')==doc['frozen_v111_manifest_sha256']
assert sha(ROOT.parent/'v108-professional-environment/sunlit-ruins-environment.blend')==doc['source_scene_sha256']
checks=[]
for module in doc['modules']:
    for layer in ('sprite','shadow'):
        rec=module[layer]
        source=ROOT/rec['raw_render']
        target=ROOT/rec['image']
        image=Image.open(source).convert('RGBA')
        pixels=np.asarray(image).copy()
        alpha_before=pixels[:,:,3].copy()
        if layer=='shadow':
            pixels[:,:,:3]=0
            Image.fromarray(pixels,'RGBA').save(target)
            rec['postprocess']={'script':'source/finalize.py','rgb_exactly_zero':True,
                'additional_alpha_floor':0,'alpha_unchanged_from_raw_render':True,
                'note':'The raw border alpha is already zero; preserve all rendered weak penumbra'}
        else:
            shutil.copyfile(source,target)
        out=np.asarray(Image.open(target))
        edge=np.concatenate((out[0,:,3],out[-1,:,3],out[:,0,3],out[:,-1,3]))
        assert edge.max()==0
        assert np.array_equal(out[:,:,3],alpha_before)
        rect=rec['source_pixel_rect']
        assert list(image.size)==[rect['width'],rect['height']]
        assert rec['foot_local_pixel']==[640-rect['x'],360-rect['y']]
        assert np.count_nonzero(out[:,:,3])>20
        rec['sha256']=sha(target)
        rec['raw_render_sha256']=sha(source)
        checks.append({'module':module['id'],'layer':layer,'size':list(image.size),
            'transparent_border':True,'alpha_identical_to_raw':True,'sha256':rec['sha256']})

doc['runtime_contract']={
    'sprite_centered':False,'sprite_offset':'-foot_local_pixel',
    'all_layers_share_instance_foot':True,
    'source_pixel_runtime':'Use 1 source pixel per Godot unit with no Camera2D zoom',
    'existing_zoom_0p65_runtime':'Scale texture by 1/0.65; use the same scaled offset and instance origin',
    'layer_order':['base_ground','ground_shadows','these_ground_decoration_sprites','actors_enemies_drops_and_aboveground_props'],
    'navigation_collision':'None. Do not create CollisionObject2D, NavigationObstacle2D or solid tiles.',
    'occlusion':'Never add these sprites to a foreground or actor-occlusion pass',
    'sparse_placement':'Only fixed, deliberate placements at true obstacle edges; reserve entrance/path/enemy-group/drop space',
    'rotation':'No runtime rotation, random yaw, flip or mirror. Light direction is baked.'}
(ROOT/'exports/manifest.json').write_text(json.dumps(doc,indent=2)+'\n')

def geometry(points):
    ring=ogr.Geometry(ogr.wkbLinearRing)
    for x,y in points+points[:1]:ring.AddPoint_2D(x,y)
    poly=ogr.Geometry(ogr.wkbPolygon)
    poly.AddGeometry(ring)
    return poly

by_old={m['id']:m for m in old_doc['modules']}
by_new={m['id']:m for m in doc['modules']}
by_collision={m['module_id']:m for m in old_collisions['modules']}
obstacles=[]
for inst in old_layout['instances']:
    for polygon in by_collision[inst['module']]['polygons']:
        x,y=inst['foot_screen_pixel']
        obstacles.append(geometry([[x+a,y+b] for a,b in polygon['outer']['foot_relative_screen_pixel']]))

placements=[
    {'id':'fern_wall_outer','module':'fern_low','foot_screen_pixel':[354,261]},
    {'id':'fern_gate_outer','module':'fern_low','foot_screen_pixel':[867,293]},
    {'id':'fern_rock_outer','module':'fern_low','foot_screen_pixel':[308,521]},
    {'id':'pebbles_wall_front','module':'pebble_trio','foot_screen_pixel':[488,281]},
    {'id':'pebbles_rock_front','module':'pebble_trio','foot_screen_pixel':[450,585]},
]
route_keep_clear=geometry([[595,315],[800,315],[800,720],[595,720]])
placement_geometries=[]
for inst in placements:
    foot=inst['foot_screen_pixel']
    module=by_new[inst['module']]
    g=geometry([[a+foot[0],b+foot[1]] for a,b in module['visual_placement_hull_foot_relative_screen_pixel']])
    assert all(g.Intersection(o).GetArea()<1e-8 for o in obstacles)
    assert not g.Intersects(route_keep_clear)
    inst['minimum_distance_to_existing_collision_pixels']=min(g.Distance(o) for o in obstacles)
    inst['no_existing_obstacle_footprint_overlap']=True
    inst['outside_sample_route_keep_clear']=True
    placement_geometries.append(g)
for i,g in enumerate(placement_geometries):
    assert all(not g.Intersects(other) for other in placement_geometries[i+1:])
sample={'schema':'sparse-ground-dressing-example-v1','viewport':[1280,720],
        'base_reference':'../v111-modular-environment/exports/assembly-layout.json',
        'instances':placements,'new_collision_count':0,'exported_asset_types':2,
        'new_decoration_instance_count':5,'route_keep_clear_rect_source_pixel':[595,315,205,405],
        'scope':'Technical example only. Root handles actual live-map placement and gameplay review.',
        'render_kind':'Real PNG alpha composite, not a native Godot screenshot'}
(ROOT/'qa/example-layout.json').write_text(json.dumps(sample,indent=2)+'\n')

def blit(canvas,base,record,foot):
    image=Image.open(base/record['image']).convert('RGBA')
    anchor=record['foot_local_pixel']
    canvas.alpha_composite(image,(round(foot[0]-anchor[0]),round(foot[1]-anchor[1])))

canvas=Image.open(OLD/'qa/assembly-ground.png').convert('RGBA')
for inst in old_layout['instances']:
    blit(canvas,OLD,by_old[inst['module']]['shadow'],inst['foot_screen_pixel'])
for inst in placements:
    blit(canvas,ROOT,by_new[inst['module']]['shadow'],inst['foot_screen_pixel'])
for inst in placements:
    blit(canvas,ROOT,by_new[inst['module']]['sprite'],inst['foot_screen_pixel'])
for inst in old_layout['instances']:
    m=by_old[inst['module']]
    if 'ground_detail' in m:blit(canvas,OLD,m['ground_detail'],inst['foot_screen_pixel'])
for inst in sorted(old_layout['instances'],key=lambda i:i['foot_screen_pixel'][1]):
    blit(canvas,OLD,by_old[inst['module']]['sprite'],inst['foot_screen_pixel'])
canvas.save(ROOT/'qa/sparse-assembly.png')

font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',17)
small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',13)
marked=canvas.copy()
draw=ImageDraw.Draw(marked)
draw.rectangle((18,18,840,76),fill=(21,29,24,230))
draw.text((30,27),'2 LOW GROUND MODULES / 5 deliberate obstacle-edge placements',font=font,fill='white')
draw.text((30,52),'Real exported PNGs, actual 1:1 source-pixel scale / no new collision / technical composite',font=small,fill='white')
for index,inst in enumerate(placements,1):
    x,y=inst['foot_screen_pixel']
    draw.ellipse((x-24,y-42,x+24,y+10),outline=(223,214,133,255),width=1)
    draw.text((x+28,y-20),str(index),font=font,fill=(250,243,179,255),stroke_width=2,stroke_fill=(30,36,27,255))
marked.save(ROOT/'qa/sparse-assembly-marked.png')

# Inspection sheet shows each actual export at production size and 6x nearest
# magnification. Magnification is plainly labeled and never used in production.
sheet=Image.new('RGBA',(1080,540),(31,39,33,255))
sd=ImageDraw.Draw(sheet)
sd.text((24,18),'REAL MODULE PIXELS / production size + 6x inspection detail',font=font,fill='white')
for index,module in enumerate(doc['modules']):
    left=20+index*540
    patch=Image.new('RGBA',(112,92))
    pd=ImageDraw.Draw(patch)
    for y in range(0,92,8):
        for x in range(0,112,8):
            c=191 if (x//8+y//8)%2 else 219
            pd.rectangle((x,y,x+7,y+7),fill=(c,c,c,255))
    anchor=(50,66)
    blit(patch,ROOT,module['shadow'],anchor)
    blit(patch,ROOT,module['sprite'],anchor)
    crop=patch.crop((18,30,84,82))
    sheet.alpha_composite(crop.resize((396,312),Image.Resampling.NEAREST),(left+20,82))
    sd.text((left+20,53),module['id']+' / 6x inspection',font=font,fill='white')
    sheet.alpha_composite(patch,(left+20,413))
    dims=module['geometry_dimensions_metres']
    sd.text((left+145,430),f'1:1 source pixels / {dims[0]:.2f} x {dims[1]:.2f} m',font=small,fill='white')
    sd.text((left+145,451),f'height {dims[2]:.2f} m / ground layer only',font=small,fill='white')
sheet.save(ROOT/'qa/module-inspection.png')

result={'result':'PASS','module_count':2,'rgba_exports':4,'new_collision_count':0,
    'batch_completed':json.loads((ROOT/'source/BATCH_COMPLETE.json').read_text()),
    'export_checks':checks,'all_shadow_alpha_preserved':True,
    'source_v108_unchanged':True,'reference_v111_manifest_unchanged':True,
    'same_camera_projection_and_sun_as_v111':True,'sample_placements':5,
    'sample_placement_envelopes_outside_existing_blockers':True,
    'sample_route_keep_clear':True,'no_sample_decoration_envelope_overlaps':True,
    'not_tested':['Native live-map integration','Actor/enemy/drop visibility in the live game'],
    'required_runtime_condition':'Decorations must remain below actors, enemies and drops'}
(ROOT/'qa/verification.json').write_text(json.dumps(result,indent=2)+'\n')
print('GROUND_DRESSING_EXPORTS_PASS: 2 modules, 4 RGBA images, 5 sparse sample placements, no collision')
