extends SceneTree
## Run only on original57, in a fresh isolated user directory; no granted progression.
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const FIXTURE := "res://docs/qa/v115-native-map-entry/earned-v114-save.json"
const PATH := "user://build_save.json"
const OUTPUT := "res://docs/qa/iron-will/"
const ROUTE := ["2151","37690","48423","6204","63976","16775","46910"]
func _initialize() -> void: call_deferred("run")
func require(ok: bool, label: String) -> void: assert(ok,label)
func write(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(OUTPUT+name,FileAccess.WRITE)
	file.store_buffer(bytes); file.close()
func normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value,"",true,true)),"",true,true)
func run() -> void:
	if Rules.VERSION != 57 or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-iron-will-"): quit(78); return
	var file := FileAccess.open(PATH,FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURE)); file.close()
	var game := Game.new()
	require(game.load_build(PATH),"Existing genuinely earned level5 fixture loads")
	require(game.snapshot().talents.class_id == 0 and game.snapshot().talents.allocated == ["58833"],"Existing formal Scion class/start reused")
	for id: String in ROUTE: require(game.allocate_passive(id,0,game.revision(),PATH).ok,"Original paid prerequisite: "+id)
	require(game.level == 5 and game.talent_points == 2 and not game.available_passives().has("50288"),"Seven paid points and frozen57 refusal")
	write("schema57-town.json",FileAccess.get_file_as_bytes(PATH))
	var stats: Dictionary = game.get_stats()
	var snapshot: Dictionary = game.get_combat_snapshot()
	var casts := {}
	for skill: String in ["basic","frost","shade_bolt"]:
		var cast: Dictionary = Compiler.compile_basic(snapshot) if skill == "basic" else Compiler.compile_group(skill,snapshot,[])
		require(cast.ok,"Original relevant cast compiles")
		casts[skill] = {"snapshot":cast.snapshot,"damage":Damage.resolve(Combat.event_packet(cast.snapshot,skill,"projectile"),cast.snapshot.modifiers)}
	var effects := {}
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).type == "mastery":
			for effect: Dictionary in Source.Data.node(id).mastery_effects:
				effects[id+":"+str(effect.effect)] = Source.node_effect(id,int(effect.effect),57)
		else: effects[id+":0"] = Source.node_effect(id,0,57)
	var frozen_hash := normalized(effects).sha256_text()
	var selected := {}
	for id: String in ["50288","12926","15842"] + ROUTE: selected[id] = Source.node_effect(id,0,57)
	var arena = load("res://scenes/main.tscn").instantiate()
	arena.state = game; arena.build_save_path = PATH
	root.add_child(arena); arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	require(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok,"Original free map draft")
	require((await arena.open_map(arena.map_draft().revision)).ok,"Formal actual map entry")
	write("schema57-active.json",FileAccess.get_file_as_bytes(PATH))
	var oracle := {"baseline":"47f31d0aeab2651f19a3590dbe6031ffb4a60830","fixture_sha256":FileAccess.get_sha256(FIXTURE),"town_sha256":FileAccess.get_sha256(OUTPUT+"schema57-town.json"),"active_sha256":FileAccess.get_sha256(OUTPUT+"schema57-active.json"),"stats":stats,"snapshot":snapshot,"casts":casts,"effects_policy57_sha256":frozen_hash,"effects_count":effects.size(),"selected_effects":selected,"route_paid":ROUTE,"level":game.level}
	write("schema57-oracle.json",(JSON.stringify(oracle,"\t",true,true)+"\n").to_utf8_buffer())
	print("SCHEMA57_CAPTURE earned level=",game.level," paid=7 remaining=",game.talent_points," strength=",stats.strength," frozen_effects=",effects.size())
	arena.free(); quit()
