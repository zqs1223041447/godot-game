extends "res://tests/area_support_native_capture.gd"
## One native batch pass; inherited helpers capture the real rendered viewport.
const Registry=preload("res://scripts/combat/support_registry.gd")
const Emblem=preload("res://scripts/visuals/skill_emblem.gd")
const Design=preload("res://scripts/visuals/visual_theme.gd")
const PROFILES: Dictionary={
	"tornado":["physical_focus","focus"],"bolt":["swift_projectiles","lightning_focus"],
	"frost":["heavy_projectiles","lingering_chill"],"nova":["breadth","concentrate"],
	"meteor":["fire_focus","concentrate"],"chain":["chain_extension","chain_reach"],
	"dash":["efficiency","quickcast"],"ward":["efficiency","quickcast"],
}
func capture(name: String) -> void:
	# Simulation is held by the fixture; refresh the real HUD from its live values.
	arena.hud._update_live()
	await super.capture(name)
func run() -> void:
	if DisplayServer.get_name()=="headless" or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-v019-native/"):
		quit(78);return
	output=OS.get_environment("GODOT_SUPPORT_BATCH_QA_DIR")
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,720)
	var fresh:=Model.new();fresh.slot_skill(0,"nova");assert(fresh.save_build()==OK)
	arena=load("res://scenes/main.tscn").instantiate()
	arena.state = preload("res://scripts/build_state.gd").new() # Explicit legacy contract fixture.
	root.add_child(arena)
	arena.set_process(false);arena.hud.set_process(false);arena.auto_fire=false
	arena.enemies.clear();arena.monster_runtime.reset();arena.spawn_timer=9999
	arena.player_pos=Vector2(700,350)
	add_targets()
	await contact_sheet()
	if OS.get_cmdline_user_args().has("--matrix-only"):
		busy=true
		await matrix()
		await area_boundary_matrix()
		write_report("batch-render-report.json")
		print("SUPPORT_BATCH_RENDER_COMPLETE")
		quit(0);return
	arena.hud.open_panel("skills");await settle();select_skill("nova")
	arena.hud._panel_scroll.ensure_control_visible(arena.hud.find_child("AddSupport_breadth",true,false));await settle()
	stage=1
	print("SUPPORT_BATCH_NATIVE_READY: click breadth and concentrate, Escape, then key1")
func add_targets() -> void:
	for offset: Vector2 in [Vector2.ZERO,Vector2(110,0),Vector2(-110,0),Vector2(0,110),Vector2(0,-110)]:
		var enemy: Dictionary=arena._spawn_monster("crawler",arena.player_pos+offset,"ordinary","normal",[])
		enemy.spawn=0.0
func _process(_delta: float) -> bool:
	if arena==null or busy:return false
	arena.queue_redraw()
	if stage==1 and arena.state.get_skill_supports("nova")==["breadth","concentrate"]:
		busy=true;call_deferred("accepted_link")
	if stage==2 and float(arena.cooldowns.get("nova",0))>0:
		busy=true;call_deferred("accepted_cast")
	return false
func accepted_link() -> void:
	arena.hud._panel_scroll.ensure_control_visible(arena.hud.find_child("SupportCastPreview",true,false))
	await capture("native-720-two-supports")
	var cast: Dictionary=arena.state.get_skill_cast("nova")
	assert(is_equal_approx(cast.recipe.radius,148.8) and is_equal_approx(cast.recipe.area_multiplier,0.9216))
	print("SUPPORT_BATCH_NATIVE_LINK_PASS")
	stage=2;busy=false
func accepted_cast() -> void:
	arena._update_effects(0.12)
	await capture("native-720-paired-nova")
	var cues: Array=arena.visual_cues.cues.filter(func(cue: Dictionary)->bool:return cue.kind=="nova")
	assert(cues.size()==1 and is_equal_approx(cues[0].radius,148.8) and arena.kills==5)
	assert(is_equal_approx(arena.mana,95.44) and arena.cooldowns.nova==6.0)
	var loaded:=Model.new();assert(loaded.load_build() and loaded._snapshot()==arena.state._snapshot())
	records.append({"stage":"native_mouse_key_720","skill":"nova","supports":["breadth","concentrate"],"radius":cues[0].radius,"area_multiplier":0.9216,"kills":arena.kills,"mana":arena.mana,"cooldown":arena.cooldowns.nova,"save_matches":true})
	print("SUPPORT_BATCH_NATIVE_INPUT_PASS "+JSON.stringify(records.back()))
	stage=3
	await matrix()
	await area_boundary_matrix()
	write_report("batch-native-report.json")
	print("SUPPORT_BATCH_NATIVE_COMPLETE")
	quit(0)
func contact_sheet() -> void:
	var layer:=CanvasLayer.new();layer.layer=100;root.add_child(layer)
	var page:=Control.new();page.size=Vector2(1280,720);page.theme=Design.create_theme();layer.add_child(page)
	var paper:=ColorRect.new();paper.color=Color("e6d5b5");paper.size=page.size;page.add_child(paper)
	var title:=Label.new();title.text="辅助图鉴 · 16种实际运行图标";title.position=Vector2(86,54);title.add_theme_font_size_override("font_size",26);page.add_child(title)
	var grid:=GridContainer.new();grid.columns=8;grid.position=Vector2(86,138);grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",26);page.add_child(grid)
	for id: String in Registry.SUPPORTS:
		var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(128,190);grid.add_child(box)
		var icon:=Emblem.new();icon.skill_id=id;icon.custom_minimum_size=Vector2(120,120);box.add_child(icon)
		var caption:=Label.new();caption.text=Registry.get_definition(id).name;caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;caption.custom_minimum_size=Vector2(128,44);caption.add_theme_font_size_override("font_size",15);box.add_child(caption)
	await capture("all16-runtime-icons")
	layer.queue_free();await process_frame
func matrix() -> void:
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size=dimensions;arena.visual_settings.ui_scale=1.1;arena.visual_settings.font_scale=1.2;arena.hud._apply_presentation()
		for skill: String in PROFILES:
			arena.state.set_skill_supports(skill,PROFILES[skill]);arena.hud.open_panel("skills");await settle();select_skill(skill)
			arena.hud._panel_scroll.scroll_vertical=0
			await capture("%s-%d-max-preview" % [skill,dimensions.x])
			var last: Control=arena.hud.find_child("AddSupport_"+str(PROFILES[skill].back()),true,false)
			arena.hud._panel_scroll.ensure_control_visible(last)
			await capture("%s-%d-max-cards" % [skill,dimensions.x])
			records.append({"stage":"programmatic_menu_render","skill":skill,"width":dimensions.x,"supports":PROFILES[skill],"visible_cards":Registry.supports_for_skill(skill).size()})
	root.size=Vector2i(2560,1440)
	for effects: int in [0,2]:
		arena.visual_settings.effects_level=effects
		for skill: String in ["nova","meteor","frost","chain"]:
			arena.hud.close_panel();arena.enemies.clear();arena.monster_runtime.reset();arena.visual_cues.reset();arena.particles.clear();arena.floating_text.clear();arena.projectiles.clear()
			arena.player_pos=Vector2(160,350) if skill=="chain" else Vector2(700,350)
			if skill=="chain":
				for i: int in range(7):
					var enemy: Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2(60+i*250,0),"ordinary","normal",[])
					enemy.spawn=0.0;enemy.health=2000.0;enemy.max_health=2000.0
			elif skill=="frost":
				for i: int in range(5):
					var enemy: Dictionary=arena._spawn_monster("crawler",arena.player_pos+Vector2.RIGHT.rotated((i-2)*0.14)*160,"ordinary","normal",[])
					enemy.spawn=0.0
			else:add_targets()
			arena.state.slot_skill(0,skill);arena.mana=130;arena.cooldowns[skill]=0
			assert(arena.cast_skill(0))
			if skill=="frost":arena._update_projectiles(0.45)
			arena._update_effects(0.12)
			await capture("play-%s-effects%d-2k" % [skill,effects])
			records.append({"stage":"programmatic_actual_cast_render","skill":skill,"effects":effects,"recipe":arena.state.get_skill_cast(skill).recipe})
func area_boundary_matrix() -> void:
	# Reuse the already accepted actual renderer pixel contract for the two new
	# reduced radii; parent fixture covers zero/breadth at the same renderer.
	const Cues=preload("res://scripts/visuals/combat_cues.gd")
	for skill: String in ["nova","meteor"]:
		for links: Array in [["concentrate"],["breadth","concentrate"]]:
			arena.state.set_skill_supports(skill,links)
			var cast: Dictionary=arena.state.get_skill_cast(skill)
			for effects: int in [0,2]:
				var viewport:=SubViewport.new();viewport.size=Vector2i(512,512);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
				var surface:=CueSurface.new();var pool:=Cues.new();pool.emit_cue(skill,Vector2(256,256),{"radius":cast.recipe.radius,"color":GameData.SKILLS[skill].color});pool.advance(0.12);surface.cues=pool.cues;surface.effects=effects;viewport.add_child(surface)
				await settle()
				var pixels: Image=viewport.get_texture().get_image();var visible: int=0
				for y: int in range(512):
					for x: int in range(512):
						if pixels.get_pixel(x,y).a>0.03:
							visible+=1;assert(Vector2(x,y).distance_to(Vector2(256,256))<=float(cast.recipe.radius)+3.0)
				var directions: int=(6 if effects==0 else 8) if skill=="nova" else 4
				for i: int in range(directions):
					var angle: float=i*TAU/directions+(0.0 if skill=="nova" else PI/4)
					var point: Vector2=Vector2(256,256)+Vector2.RIGHT.rotated(angle)*(float(cast.recipe.radius)-2.0)
					var seen: bool=false
					for dy: int in range(-3,4):
						for dx: int in range(-3,4):seen=seen or pixels.get_pixel(roundi(point.x)+dx,roundi(point.y)+dy).a>0.03
					assert(seen)
				assert(visible>20)
				records.append({"stage":"reduced_area_pixel_bounds","skill":skill,"supports":links,"radius":cast.recipe.radius,"effects":effects,"visible_pixels":visible,"boundary_directions":directions,"pass":true})
				viewport.queue_free();await process_frame
