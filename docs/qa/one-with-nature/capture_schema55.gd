extends SceneTree
## Run only against ded5954 before schema56 changes; never a player save.
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const FIXTURE := "res://docs/qa/v115-native-map-entry/earned-v114-save.json"
const PATH := "user://build_save.json"
const OUTPUT := "res://docs/qa/one-with-nature/"
const ROUTE := ["39821","52904","444","61306","54142","30894"]
func _initialize() -> void: call_deferred("run")
func require(ok: bool) -> void:
	assert(ok, "Baseline capture must use legal production transactions")
func copy_save(name: String) -> void:
	var file := FileAccess.open(OUTPUT + name, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(PATH))
func run() -> void:
	if Rules.VERSION != 55 or not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-one-with-nature-"): quit(78); return
	var fixture_sha := FileAccess.get_sha256(FIXTURE)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURE)); file.close()
	var game := Game.new()
	require(game.load_build(PATH))
	require(game.select_class(2,game.revision(),PATH).ok)
	for id: String in ROUTE: require(game.allocate_passive(id,0,game.revision(),PATH).ok)
	require(Rules.reason(game.snapshot()).is_empty() and game.talent_points == 3)
	require(not game.available_passives().has("15842"))
	copy_save("schema55-town.json")
	var arena = load("res://scenes/main.tscn").instantiate()
	arena.state = game; arena.build_save_path = PATH
	root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	require(arena.craft_normal_map("old_garden",1,[],[],arena.map_draft().revision).ok)
	var entered: Dictionary = await arena.open_map(arena.map_draft().revision)
	print("BASELINE_ENTRY ",JSON.stringify(entered))
	if not entered.ok: arena.free(); quit(1); return
	require(Rules.reason(game.snapshot()).is_empty() and not game.snapshot().journey.active_run.is_empty())
	copy_save("schema55-active.json")
	var nodes := {}
	for id: String in ["18670","25511","30894","56646","64878","15842"]: nodes[id] = Source.node_effect(id,0,55)
	var oracle := {"baseline":"ded595477a73f91c1b1e60bf0d93919c88941103","earned_fixture_sha256":fixture_sha,
		"town_sha256":FileAccess.get_sha256(OUTPUT+"schema55-town.json"),"active_sha256":FileAccess.get_sha256(OUTPUT+"schema55-active.json"),
		"active_stats":game.get_stats(),"nodes_policy55":nodes,"checks":"Actual earned level5, class switch, six paid prerequisites and existing free old_garden entry; no injected funds, items or unlocks"}
	file = FileAccess.open(OUTPUT+"schema55-oracle.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(oracle,"\t",true,true)+"\n"); file.close()
	require(FileAccess.get_sha256(FIXTURE) == fixture_sha)
	arena.free()
	print("SCHEMA55_CAPTURE legal town and active run; original earned fixture unchanged")
	quit()
