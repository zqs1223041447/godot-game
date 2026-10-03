extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Gems = preload("res://scripts/items/gem_catalog.gd")
var checks := 0
var failures := 0
func _initialize()->void: call_deferred("run")
func run()->void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-v022-capacity-"): quit(78); return
	var state = Model.new()
	check(state.bag_layout()=={"columns":12,"rows":10,"pages":2},"Model supplies 240 actual cells")
	var full: Dictionary = state.snapshot()
	for uid: String in full.locations.keys():
		if full.locations[uid].kind == "bag":full.locations.erase(uid);full.items.erase(uid)
	for index: int in range(240):
		var uid := "capacity_%03d"%index
		full.items[uid]=Gems.create_instance(uid,"support:focus")
		full.locations[uid]={"kind":"bag","page":int(index/120),"x":index%12,"y":int((index%120)/12)}
	check(Rules.reason(full).is_empty(),"All 240 single-cell items pass the complete current schema")
	var path := "user://full-240.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(full,"\t",true,true))
	check(state.load_build(path),"240-item bag loads through the real store")
	var before: Dictionary=state.snapshot()
	check(state.award_gem("support:volley").is_empty() and state.snapshot()==before,"The 241st gem cannot become hidden overflow")
	var rng:=RandomNumberGenerator.new();rng.seed=160240;var rng_before:=rng.state
	check(state.award_equipment(rng,30,"rare").is_empty() and rng.state==rng_before and state.snapshot()==before,"Full-bag equipment admission restores RNG and the full snapshot")
	check(not state.can_move_item("guardian_robe",{"kind":"bag","page":1,"x":11,"y":9},state.revision()),"A multi-cell item cannot overflow the expanded lower-right corner")
	check(state.discard_item("capacity_238",state.revision(),path).ok,"A user transaction frees exactly one new-region cell")
	var uid: String=state.award_gem("support:volley")
	check(not uid.is_empty() and state.location(uid)=={"kind":"bag","page":1,"x":10,"y":9},"Real gem reward fills the released cell beyond v15 bounds")
	check(state.save_build(path)==OK,"Current coordinates save successfully")
	var loaded=Model.new()
	check(loaded.load_build(path) and loaded.snapshot()==state.snapshot(),"Expanded coordinates round-trip with every UID")
	var arranged: Dictionary=state.arrange_items(state.revision(),path)
	check((arranged.ok or arranged.error_code=="no_change") and state.pending_items().is_empty() and Rules.reason(state.snapshot()).is_empty(),"240-item organization stays valid and cannot use recovery as storage")
	var typed: Dictionary=Rules.decode_v15(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v022_currency/v15-wallet-27.json")))
	check(not typed.is_empty() and Rules.reason_v15(typed).is_empty(),"Literal v15 input remains valid under its frozen decoder")
	var moved_uid: String=""
	for id: String in typed.items:
		if typed.items[id].kind=="support_gem" and typed.locations[id].kind=="bag":moved_uid=id;break
	for point: Vector2i in [Vector2i(8,0),Vector2i(0,6),Vector2i(11,9)]:
		var injected: Dictionary=typed.duplicate(true)
		injected.locations[moved_uid]={"kind":"bag","page":1,"x":point.x,"y":point.y}
		check(Rules.decode_v15(injected).is_empty() and not Rules.reason_v15(injected).is_empty(),"v15 cannot import newly unlocked coordinates %s"%point)
		injected.version=16;injected.crafting.erase("materials")
		check(Rules.reason(Rules.decode(injected)).is_empty(),"The same coordinate is a valid current-schema positive control")
	for point: Vector2i in [Vector2i(12,0),Vector2i(0,10),Vector2i(-1,0)]:
		var invalid: Dictionary=state.snapshot();invalid.locations[uid]={"kind":"bag","page":1,"x":point.x,"y":point.y}
		check(not Rules.reason(invalid).is_empty(),"Current schema still rejects coordinate %s"%point)
	print("Expanded bag capacity: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
