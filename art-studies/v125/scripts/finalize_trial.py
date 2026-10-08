"""Reload isolated sample for a focused integrity/configuration check; no renders."""
import bpy,json,hashlib,os
from pathlib import Path
P=Path(os.environ['V125_OUTPUT_DIR']).expanduser().resolve();bpy.ops.wm.open_mainfile(filepath=str(P/'ranger-locomotion-trial.blend'),load_ui=False);s=bpy.context.scene;m=json.loads((P/'reports/trial-metadata.json').read_text());sig=json.loads((P/'reports/invariants.json').read_text())
ARMS=[bpy.data.objects[n] for n in ['Armature','Armature.001','Armature.002']]
def ahash(a):
 return hashlib.sha256(json.dumps([[f.data_path,f.array_index,[(list(k.co),k.interpolation,list(k.handle_left),list(k.handle_right)) for k in f.keyframe_points]] for f in a.fcurves],separators=(',',':')).encode()).hexdigest()
assert all(ahash(bpy.data.actions[n])==h for n,h in sig['original_action_hashes'].items())
assert all(bpy.data.objects[n].animation_data.action.name=='Trial_Walk80_Jog20_Loop' for n in ['Armature','Armature.001','Armature.002'])
s['trial_status']=m['status'];s['geometry_acceptance']=m['geometry_acceptance'];s['visual_acceptance']=m['visual_acceptance']
for o in bpy.data.objects:
 if o.type=='MESH':
  char=o.parent in ARMS or o.name=='Skinned_Shoulder_Lining_Bridge';o.hide_render=not char
  if char:o.visible_camera=True
s.render.engine='CYCLES';s.cycles.samples=12;s.cycles.use_denoising=False;s.cycles.device='CPU';s.cycles.seed=125;s.render.threads_mode='FIXED';s.render.threads=8;s.render.film_transparent=True;s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.image_settings.color_depth='8';s.frame_set(0)
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(P/'ranger-locomotion-trial.blend'),compress=True)
q={'saved_sample_reopened':True,'original_actions_preserved_after_reload':True,'original_action_count':len(sig['original_action_hashes']),'all_three_rigs_use_same_trial_action':True,'animation_display_period_seconds_external_to_virtual_bake':m['variants']['candidate']['cycle_seconds'],'transparent_render_configuration_saved':True,'further_renders':0,'geometry_status':m['geometry_acceptance'],'visual_status':m['visual_acceptance']}
(P/'reports/final-reload-check.json').write_text(json.dumps(q,indent=2));print(json.dumps(q))
