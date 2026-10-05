extends SceneTree
## Small same-input real normal-profile death/flush comparison. No timing gate.
const Model = preload("res://scripts/canonical_game_state.gd")
const Arena = preload("res://scripts/main.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
class ObservedState extends "res://scripts/canonical_game_state.gd":
	var fail_write := false
	var talent_us := 0
	var talent_calls := 0
	var admissions: Array = []
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_write else super._write_bytes(path,bytes)
	func _admit_reward_item(item: Dictionary) -> bool:
		var accepted := super._admit_reward_item(item)
		admissions.append([item.uid,accepted,revision()])
		return accepted
	func timed_talents(candidate: Dictionary) -> String:
		var began := Time.get_ticks_usec()
		var reason: String = Rules.SourceTree.reason(candidate)
		talent_us += Time.get_ticks_usec()-began; talent_calls += 1
		return reason
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
func run() -> void:
	var output := OS.get_environment("V051_REWARD_OUT")
	var data := OS.get_environment("XDG_DATA_HOME")
	if not data.begins_with("/tmp/godot-m1-v051-") or output.is_empty() or FileAccess.file_exists("user://build_save.json"):
		push_error("Fresh isolated v051 user data and V051_REWARD_OUT required");quit(78);return
	var mode := OS.get_environment("V051_CASE")
	var observed := mode != "plain"
	var state = ObservedState.new() if observed else Model.new()
	var uid := "gear_%06d" % int(state.snapshot().next_item_serial)
	check(state._admit_reward_item(Items.wrap_equipment({"id":uid,"base_id":"cinder_reed","rarity":"magic","item_level":30,"affixes":[{"id":"deepwell","tier":1,"value":5}]})),"Admit current legal gear fixture")
	var candidate: Dictionary = state.snapshot()
	check(state._set_bag_currency_balance(candidate,100).ok,"Fixture shard supply uses current rules")
	var prior_kills := 58 if mode == "failed_save" else 0
	candidate.journey.normal_root_kills = prior_kills
	candidate.journey.claimed_gems = prior_kills / 30
	if mode == "full_bag":
		for old_uid: String in candidate.locations.keys():
			if candidate.locations[old_uid].kind == "bag":
				candidate.locations.erase(old_uid);candidate.items.erase(old_uid)
		for page: int in range(2):
			for y: int in range(10):
				for x: int in range(12):
					var id := "item_%06d" % int(candidate.next_item_serial);candidate.next_item_serial += 1
					candidate.items[id] = Model.Gems.create_instance(id,"support:focus")
					candidate.locations[id] = {"kind":"bag","page":page,"x":x,"y":y}
	check(Rules.reason(candidate).is_empty(),"Complete candidate fixture valid")
	state._accept_memory(candidate);check(state.save_build("user://build_save.json")==OK,"Normal exact-path save succeeds")
	var arena := Arena.new();arena.state=state;root.add_child(arena);arena.set_process(false);arena.set_physics_process(false);arena.hud.set_process(false)
	check(arena.leave_normal_town(arena.world_context().revision).ok,"Actual normal arena entrance")
	while arena.hud.is_blocking():arena.hud.close_panel()
	arena.rng.seed=500037;arena.reward_kills=prior_kills;arena.enemies.clear();arena.monster_runtime.reset();arena.telegraphs.reset();arena.auto_fire=false;arena.spawn_timer=100000.0
	for index: int in range(20):
		var enemy: Dictionary=arena.monster_runtime.create_root("crawler",1,arena.player_pos+Vector2(80+index*3,0),"ordinary","normal",[],true)
		check(not enemy.is_empty() and enemy.reward_eligible,"Actual legal normal root")
		enemy.spawn=0.0;arena.enemies.append(enemy)
	# Initial critical RNG was randomized at scene startup in the retained baseline,
	# but these direct settlements emit no critical events. Replay that exact unused
	# checkpoint for paired runs instead of deleting RNG from the equality record.
	var baseline_path := OS.get_environment("V051_MATCH_INITIAL_RNG_FROM")
	if not baseline_path.is_empty():
		var original: Dictionary=bytes_to_var(FileAccess.get_file_as_bytes(baseline_path))
		assert(original.critical_rng.draws==0 and original.critical_rng.events==0)
		arena.critical_runtime.restore(original.critical_rng)
	var notifications: Array=[]
	var weak: WeakRef = weakref(state)
	state.changed.connect(func():
		var current=weak.get_ref();notifications.append([current.revision(),current.snapshot().items.keys(),current._busy]))
	if observed:
		state.admissions.clear();state.talent_us=0;state.talent_calls=0
		if mode == "instrumented":state._talent_validator=state.timed_talents
		state.fail_write=mode=="failed_save"
	var save_before:=FileAccess.get_file_as_bytes("user://build_save.json")
	var saves_before: int=state.successful_saves
	await process_frame;await process_frame
	var started:=Time.get_ticks_usec();arena._begin_progress_transaction();var began:=Time.get_ticks_usec()
	for enemy: Dictionary in arena.enemies:arena._damage_enemy(enemy,float(enemy.health)+float(enemy.shield)+1.0,Color.WHITE)
	var death_us:=Time.get_ticks_usec()-began;began=Time.get_ticks_usec();arena._end_progress_transaction();var flush_us:=Time.get_ticks_usec()-began;var total_us:=Time.get_ticks_usec()-started
	check(arena.kills==20 and arena.reward_kills==prior_kills+20,"All20 roots settled exactly once")
	check(int(state.normal_journey().normal_root_kills)==prior_kills+20,"Persistent normal root count")
	var failure_receipt: Dictionary={}
	if mode=="failed_save":
		check(arena._progress_save_dirty and state.successful_saves==saves_before,"Failed write keeps dirty progress")
		check(FileAccess.get_file_as_bytes("user://build_save.json")==save_before,"Failed write protects previous disk bytes")
		var memory:=var_to_bytes(state.snapshot());var random_state: int=arena.rng.state
		failure_receipt={"memory":memory,"rng":random_state,"disk":save_before,"attempts":state.save_attempts}
		state.fail_write=false;check(arena._flush_progress(true),"Explicit retry succeeds")
		check(var_to_bytes(state.snapshot())==memory and arena.rng.state==random_state,"Retry preserves reward memory and RNG")
	else:check(state.successful_saves==saves_before+1,"Only one final successful batch save")
	check(not arena._progress_save_dirty and Rules.reason(state.snapshot()).is_empty(),"Final complete build valid and flushed")
	var disk:=FileAccess.get_file_as_bytes("user://build_save.json")
	check(disk==JSON.stringify(state.snapshot(),"\t",true,true).to_utf8_buffer(),"Exact final disk equals canonical memory")
	var observation: Dictionary={"state":state.snapshot(),"uid_order":state.snapshot().items.keys(),"rng":arena.rng.state,"critical_rng":arena.critical_runtime.checkpoint(),"flasks":arena.flask_runtime.snapshot(),"notifications":notifications,"enemies":arena.enemies,"damage_trace":arena.damage_trace,"burn_trace":arena.burn_trace,"event_counts":arena.event_counts,"feedback":arena.damage_feedback,"legacy_text":arena.floating_text,"particles":arena.particles,"health":arena.health,"mana":arena.mana,"shield":arena.shield,"kills":arena.kills,"reward_kills":arena.reward_kills,"total_damage":arena.total_damage,"save_attempts":state.save_attempts,"successful_saves":state.successful_saves,"final_disk":disk,"failed_save":failure_receipt}
	if observed:observation.admissions=state.admissions
	var bytes:=var_to_bytes(observation);FileAccess.open(output+".bin",FileAccess.WRITE).store_buffer(bytes)
	var report: Dictionary={"mode":mode,"checks":checks,"failures":failures,"same_host_cpu_only":true,"unwrapped_production_model":not observed,"synchronous_us":total_us,"death_us":death_us,"flush_us":flush_us,"typed_observation_bytes":bytes.size(),"observation_sha256":digest(bytes),"disk_bytes":disk.size(),"disk_sha256":digest(disk),"changed_signals":notifications.size(),"root_deaths":20,"items_after":state.snapshot().items.size(),"talent_nested_us":state.talent_us if observed else 0,"talent_calls":state.talent_calls if observed else 0,"source_revision":OS.get_environment("V051_SOURCE")}
	FileAccess.open(output+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true));print(JSON.stringify(report));arena.queue_free();await process_frame;quit(1 if failures else 0)
