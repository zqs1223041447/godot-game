extends SceneTree
## Baseline-only capture; lawful roots earn the route budget through actual Main.
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const FIXTURE := "res://docs/qa/v115-native-map-entry/earned-v114-save.json"
const PATH := "user://build_save.json"
const OUTPUT := "res://docs/qa/iron-grip/"
const ROUTE := ["39821","52904","444","61306","63139","5408","11497","238","10829","16167","19144","28330","46578"]
func _initialize() -> void: call_deferred("run")
func require(ok: bool, label: String) -> void: assert(ok,label)
func write(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(OUTPUT+name,FileAccess.WRITE)
	file.store_buffer(bytes); file.close()
func run() -> void:
	if Rules.VERSION != 56 or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-iron-grip-"): quit(78); return
	var file := FileAccess.open(PATH,FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURE)); file.close()
	var game := Game.new()
	require(game.load_build(PATH),"Earned fixture loads")
	require(game.select_class(2,game.revision(),PATH).ok,"Actual Ranger selection")
	var arena = load("res://scenes/main.tscn").instantiate()
	arena.state = game; arena.build_save_path = PATH
	root.add_child(arena); arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	var maps := 0
	var roots_before: int = game.normal_journey().normal_root_kills
	while game.level < 10 and maps < 6:
		require(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok,"Free starter draft")
		require((await arena.open_map(arena.map_draft().revision)).ok,"Actual map entry")
		arena._begin_progress_transaction()
		for round_index: int in range(8):
			arena._flush_monster_spawns()
			for enemy: Dictionary in arena.enemies.duplicate():
				if enemy.health <= 0.0: continue
				enemy.spawn = 0.0
				arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+10000.0,Color.WHITE)
			arena._flush_monster_spawns(); arena._check_map_complete()
			if arena.world_context().mode == "map_complete": break
		arena._end_progress_transaction()
		require(arena.world_context().mode == "map_complete","Finite roots/descendants clear")
		require(arena.return_to_town(arena.world_context().revision).ok,"Formal town return")
		require(arena.claim_normal_rewards(arena.world_context().revision).ok,"Existing earned rewards claim")
		maps += 1
	require(game.level >= 10 and game.talent_points >= 14,"Actual reward settlement earned at least14 points")
	for id: String in ROUTE: require(game.allocate_passive(id,0,game.revision(),PATH).ok,"Existing paid predecessor: "+id)
	require(not game.available_passives().has("12926") and Rules.reason(game.snapshot()).is_empty(),"Frozen56 blocks Iron Grip")
	write("schema56-town.json",FileAccess.get_file_as_bytes(PATH))
	var stats: Dictionary = game.get_stats()
	var snapshot: Dictionary = game.get_combat_snapshot()
	var casts := {}
	for skill: String in ["basic","tornado","cleave","frost"]:
		var cast: Dictionary = Compiler.compile_basic(snapshot) if skill == "basic" else Compiler.compile_group(skill,snapshot,[])
		require(cast.ok,"Baseline cast compiles")
		var role := "parent" if skill == "tornado" else "direct" if skill == "cleave" else "projectile"
		casts[skill] = {"snapshot":cast.snapshot,"damage":Damage.resolve(Combat.event_packet(cast.snapshot,skill,role),cast.snapshot.modifiers)}
	var effects := {}
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).type == "mastery":
			for effect: Dictionary in Source.Data.node(id).mastery_effects:
				effects[id+":"+str(effect.effect)] = Source.node_effect(id,int(effect.effect),56)
		else: effects[id+":0"] = Source.node_effect(id,0,56)
	require(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok,"Active sample draft")
	require((await arena.open_map(arena.map_draft().revision)).ok,"Active sample actual entry")
	write("schema56-active.json",FileAccess.get_file_as_bytes(PATH))
	var oracle := {"baseline":"904fd5e5e61f8169dda07e91566364d6bd42bfb6","fixture_sha256":FileAccess.get_sha256(FIXTURE),"town_sha256":FileAccess.get_sha256(OUTPUT+"schema56-town.json"),"active_sha256":FileAccess.get_sha256(OUTPUT+"schema56-active.json"),"stats":stats,"snapshot":snapshot,"casts":casts,"effects_policy56":effects,"earned_maps":maps,"earned_roots":game.normal_journey().normal_root_kills-roots_before,"level":game.level,"route_paid":ROUTE}
	write("schema56-oracle.json",(JSON.stringify(oracle,"\t",true,true)+"\n").to_utf8_buffer())
	print("SCHEMA56_CAPTURE level=",game.level," maps=",maps," roots=",oracle.earned_roots," frozen_effects=",effects.size())
	arena.free(); quit()
