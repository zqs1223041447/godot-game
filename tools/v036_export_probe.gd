extends SceneTree
func _initialize()->void:
	var output:=OS.get_environment("V036_PACK_QA");var expected_font:=OS.get_environment("V036_PACK_FONT_SHA256")
	if output.is_empty() or expected_font.length()!=64:quit(78);return
	DirAccess.make_dir_recursive_absolute(output)
	var model=load("res://scripts/canonical_game_state.gd").new();var font:=load("res://assets/fonts/arena_sans.otf") as FontFile;font.allow_system_fallback=false
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(font.data);var font_hash:=h.finish().hex_encode()
	var version:=str(ProjectSettings.get_setting("application/config/version"));var directory:=str(ProjectSettings.get_setting("application/config/custom_user_dir_name"))
	var ok:bool=version=="0.36.0" and directory=="godot-game-preview-v021" and model.snapshot().version==23 and model.bag_layout()=={"pages":2,"columns":12,"rows":10} and font_hash==expected_font
	var maps=load("res://scripts/world/map_compiler.gd");var factory_type=load("res://scripts/monsters/monster_runtime.gd");var admission=load("res://scripts/world/map_admission.gd")
	var monsters=load("res://scripts/monsters/monster_catalog.gd");var attacks=load("res://scripts/combat/telegraphed_area_runtime.gd");var art=load("res://scripts/visuals/telegraph_renderer.gd");var settings=load("res://scripts/visuals/visual_settings.gd").new();settings.effects_level=0
	var rows:Array=[]
	for id:String in ["old_garden","broken_ruins"]:
		var profile:Dictionary=maps.compile(id,[],[]).profile;var factory=factory_type.new();var result:Dictionary=admission.create_root(factory,profile,"rift_warden",profile.wave,Vector2(120,0),"map_boss","",[],true)
		ok=ok and result.ok
		var enemy:Dictionary=result.enemy;enemy.spawn=0.0;var policy:Dictionary=monsters.telegraph_policy(enemy);var center:Vector2=enemy.pos if policy.target_rule=="self_at_start" else Vector2.ZERO
		var runtime=attacks.new();var begun:Dictionary=runtime.start(enemy,center,policy.profile,policy.visual_pattern);var primitives:Array=art.primitives([begun.attack],settings)
		var boundaries:=0
		for primitive:Dictionary in primitives:
			if primitive.role=="danger_boundary":boundaries+=1;ok=ok and primitive.center==center and primitive.radius==policy.profile.radius
		var events:Array=runtime.advance(policy.profile.windup_seconds,[enemy]);ok=ok and begun.ok and boundaries==2 and events.size()==1 and events[0].center==center and events[0].visual_pattern==profile.boss_attack_id
		rows.append({"map_id":id,"attack_id":profile.boss_attack_id,"target_rule":policy.target_rule,"center":[center.x,center.y],"radius":policy.profile.radius,"windup":policy.profile.windup_seconds,"physical_damage":events[0].packet.base.physical,"low_effect_boundaries":boundaries})
	for character:String in "近身震地断垣落印圆圈".split(""):ok=ok and font.has_char(character.unicode_at(0))
	var report:Dictionary={"ok":ok,"game_version":version,"schema":model.snapshot().version,"save_directory":directory,"actual_user_dir":OS.get_user_data_dir(),"bag_layout":model.bag_layout(),"font_sha256":font_hash,"engine":Engine.get_version_info().string,"map_bosses":rows,"scope":"Packed map-boss policies, fixed events and low-effect boundaries only; unchanged older mechanics reuse prior evidence"}
	FileAccess.open(output.path_join("packed-runtime-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	FileAccess.open(output.path_join("GODOT_LICENSE.txt"),FileAccess.WRITE).store_string(Engine.get_license_text());FileAccess.open(output.path_join("GODOT_COPYRIGHT.txt"),FileAccess.WRITE).store_string(JSON.stringify(Engine.get_copyright_info(),"\t",true,true))
	var licenses:Dictionary=Engine.get_license_info();var names:=licenses.keys();names.sort();var text:="Godot 4.6.3 third-party license texts\n\n"
	for name:String in names:text+=name+"\n"+str(licenses[name])+"\n\n"
	FileAccess.open(output.path_join("GODOT_THIRD_PARTY_LICENSES.txt"),FileAccess.WRITE).store_string(text);print(JSON.stringify(report));quit(0 if ok else 1)
