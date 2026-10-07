extends SceneTree
## Focused new-ID scheduler, geometry and render contract. No Main, save or battle.
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Bosses = preload("res://scripts/monsters/map_boss_profiles.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Renderer = preload("res://scripts/visuals/telegraph_renderer.gd")
const Settings = preload("res://scripts/visuals/visual_settings.gd")
const PATTERN := "ruins_garden_slam"
const CENTER := Vector2(400, 500)
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL: " + label)
func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0000001, label)
func enemy() -> Dictionary:
	return {"id":1,"root_id":1,"generation":0,"template_id":"rift_warden","rarity":"boss",
		"map_boss_attack_id":PATTERN,"pos":Vector2(200,500),"health":100.0,"spawn":0.0,
		"death_processed":false,"damage":100.0,"attack_speed":Monsters.BASE_ATTACK_SPEED,
		"contact_weights":{"physical":0.5,"fire":0.3,"cold":0.2}}
func start(runtime: RefCounted, source: Dictionary) -> Dictionary:
	var policy: Dictionary = Monsters.telegraph_policy(source)
	return runtime.start(source, CENTER, policy.profile, policy.visual_pattern)
func run_sequence(parts: Array) -> Array:
	var source := enemy(); var runtime := Runtime.new(); var events: Array = []
	check(start(runtime,source).ok, "Sequence admits")
	for delta: float in parts: events.append_array(runtime.advance(delta,[source]))
	return events
func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-v120-"): quit(78); return
	var definition := Bosses.definition(PATTERN)
	check(definition.name == "庭园缠印" and definition.target_rule == "player_at_start" and definition.trigger_distance == 420.0, "Strict player-locked map authority")
	check(definition.profile == {"radius":90.0,"windup_seconds":1.15,"recovery_seconds":1.9,"damage_multiplier":0.65}, "Exact first-stage values")
	check(definition.second_pulse == {"shape":"annulus","inner_radius":90.0,"radius":210.0,"windup_seconds":1.0} and definition.pulse_count == 2 and definition.pulse_interval == 1.0, "Exact second-stage values")
	var source := enemy(); var runtime := Runtime.new()
	var result := start(runtime,source)
	check(result.ok and runtime.has_timed_sequence_actions(), "Starts one existing timed sequence")
	var initial := runtime.state_for(1)
	check(initial.center == CENTER and initial.center != source.pos and initial.shape == "circle" and initial.pulse_index == 0, "First circle uses caller-frozen player point")
	result.attack.center = Vector2.ZERO; result.attack.second_pulse.radius = 999.0
	check(runtime.state_for(1) == initial, "Returned start state cannot mutate frozen authority")
	check(runtime.advance(1.149,[source]).is_empty(), "First complete warning cannot fire early")
	var first := runtime.advance(0.001,[source])
	check(first.size() == 1, "First deadline emits exactly once")
	if first.size() != 1: finish(); return
	check(first[0].shape == "circle" and first[0].radius == 90.0 and first[0].inner_radius == 0.0 and first[0].pulse_index == 0, "First receipt geometry")
	near(first[0].attack_age,1.15,"First deadline")
	var ring := runtime.state_for(1)
	check(ring.center == CENTER and ring.shape == "annulus" and ring.inner_radius == 90.0 and ring.profile.radius == 210.0 and ring.profile.windup_seconds == 1.0 and ring.pulse_index == 1, "Second full warning switches shape but never center")
	near(ring.elapsed,0.0,"Second visual local clock starts at zero")
	var expected_packet: Dictionary = first[0].packet.duplicate(true)
	check(expected_packet.base == {"physical":32.5,"fire":19.5,"cold":13.0} and expected_packet.tags == ["attack","area","hit"], "Each typed packet has exact 0.65 contact budget")
	check(first[0].profile_id == "ruins_garden_inner_outer" and expected_packet.skill_id == first[0].profile_id and first[0].balance_version == "original-ruins-garden-inner-outer-v1" and first[0].schema_version == 1, "Own receipt identity without schema change")
	first[0].packet.base.fire = 999.0; first[0].center = Vector2.ZERO
	source.pos = Vector2(800,900); source.damage = 9999.0; source.attack_speed = 10000.0
	check(runtime.advance(0.999,[source]).is_empty(), "Second complete warning cannot fire early after source movement")
	var second := runtime.advance(0.001,[source])
	check(second.size() == 1, "Second deadline emits exactly once")
	if second.size() != 1: finish(); return
	check(second[0].type == "annulus_attack" and second[0].inner_radius == 90.0 and second[0].radius == 210.0 and second[0].center == CENTER, "Second receipt retains locked point and authored annulus")
	check(second[0].packet == expected_packet and second[0].attack_id == initial.attack_id and second[0].source_id == 1, "Second event preserves original cast/source/frozen packet")
	near(second[0].attack_age,2.15,"Second deadline includes both full warnings")
	check(runtime.state_for(1).phase == "recovery", "Recovery only after second event")
	check(runtime.advance(1.899,[source]).is_empty() and runtime.active_count() == 1, "Frozen recovery cannot shorten after live speed change")
	check(runtime.advance(0.001,[source]).is_empty() and runtime.active_count() == 0 and runtime.advance(100,[source]).is_empty(), "Recovery finishes without replay or automatic repeat")
	var whole := run_sequence([100.0]); var split := run_sequence([0.3,0.3,0.55,0.25,0.75,1.9])
	check(whole.size() == 2 and split.size() == 2, "Large and partitioned frames each emit two events")
	for index: int in range(mini(whole.size(), split.size())):
		whole[index].erase("step_time"); split[index].erase("step_time")
		check(whole[index] == split[index], "Partition-independent event authority %d" % index)
	for speed: float in [0.2,Monsters.BASE_ATTACK_SPEED,2.0]:
		source = enemy(); source.attack_speed = speed; runtime = Runtime.new()
		check(start(runtime,source).ok,"Existing speed policy admits")
		var policy: Dictionary = Monsters.telegraph_policy(source)
		near(policy.profile.recovery_seconds,clampf(1.9*Monsters.BASE_ATTACK_SPEED/maxf(0.2,speed),0.001,60.0),"Only recovery scales with speed")
		check(runtime.advance(2.15,[source]).size() == 2,"Attack speed preserves complete warnings")
	# Existing pause/cancellation contract remains authoritative; no new scheduler.
	for age: float in [0.5,1.4]:
		source = enemy(); runtime = Runtime.new(); start(runtime,source); runtime.advance(age,[source])
		var before := runtime.state_for(1)
		check(runtime.advance(0.4,[source],true,{1:0.4}).is_empty() and runtime.state_for(1) == before,"Full frozen prefix pauses active stage")
		var resumed := runtime.advance(3.0,[source],true,{1:0.2})
		check(resumed.size() == (2 if age < 1.15 else 1), "Thaw emits only remaining stages")
	for mode: String in ["dead","removed","birth","processed","cancel","reset"]:
		source = enemy(); runtime = Runtime.new(); start(runtime,source); runtime.advance(1.2,[source])
		var live: Array = [source]
		match mode:
			"dead": source.health = 0.0
			"removed": live = []
			"birth": source.spawn = 0.1
			"processed": source.death_processed = true
			"cancel": runtime.cancel(1)
			"reset": runtime.reset()
		check(runtime.advance(10,live).is_empty() and runtime.active_count() == 0,"No second-stage settlement after " + mode)
	for field: String in ["radius","windup_seconds","damage_multiplier","recovery_seconds"]:
		source = enemy(); var profile: Dictionary = Monsters.telegraph_policy(source).profile
		profile[field] += 0.1; runtime = Runtime.new()
		check(not runtime.start(source,CENTER,profile,PATTERN).ok and runtime.active_count() == 0,"Reject forged authority " + field)
	for pattern: String in ["","unknown","ginkgo_shelter_slam","sunwell_echo"]:
		source = enemy(); runtime = Runtime.new()
		check(not runtime.start(source,CENTER,Monsters.telegraph_policy(source).profile,pattern).ok,"Reject substituted visual authority: " + pattern)
	for field: String in ["root_id","generation","template_id","rarity"]:
		source = enemy()
		match field:
			"root_id": source.root_id = 2
			"generation": source.generation = 1
			"template_id": source.template_id = "crawler"
			"rarity": source.rarity = "rare"
		runtime = Runtime.new()
		check(not runtime.start(source,CENTER,definition.profile,PATTERN).ok,"Reject non-root or wrong-map source " + field)
	var event := {"shape":"annulus","center":CENTER,"inner_radius":90.0,"radius":210.0}
	for probe: Array in [[0.0,false],[74.99,false],[75.0,true],[90.0,true],[150.0,true],[225.0,true],[225.01,false]]:
		check(Runtime.overlaps(event,CENTER+Vector2(probe[0],0),15.0) == probe[1],"Ring body boundary at d=" + str(probe[0]))
	check(Runtime.overlaps({"shape":"circle","center":CENTER,"radius":90.0},CENTER+Vector2(105,0),15.0),"First-stage outer tangent remains inclusive")
	# Renderer consumes the same state, keeping the safe center empty at all quality levels.
	for effects: int in range(3):
		var settings := Settings.new(); settings.effects_level = effects; ring.elapsed = 0.5
		var primitives := Renderer.primitives([ring],settings); var fills := 0; var inner := 0; var outer := 0
		check(primitives.size() <= Renderer.MAX_PRIMITIVES_PER_SOURCE,"Bounded ring primitives")
		for primitive: Dictionary in primitives:
			if primitive.kind == "annulus":
				fills += 1; check(primitive.inner_radius == 90.0 and primitive.radius == 210.0 and primitive.center == CENTER,"Annular tint preserves exact hole")
			elif primitive.kind == "circle":
				check(not primitive.filled,"Safe center is never a filled disk")
				if primitive.role == "danger_inner_boundary": inner += 1; check(primitive.radius == 90.0,"True inner boundary")
				elif primitive.role == "danger_boundary": outer += 1; check(primitive.radius == 210.0,"True outer boundary")
		check(fills == 1 and inner == 2 and outer == 2,"Both ring boundaries survive every effects level")
	ring.visual_pattern = "unknown"
	check(Renderer.primitives([ring]).is_empty(),"Unknown visual pattern never gains annulus admission")
	finish()
func finish() -> void:
	var report := {"checks":checks,"failures":failures,"scope":"Focused new map-ID runtime, copied render primitives and geometry; no Main, natural combat, visual capture or save migration"}
	var file := FileAccess.open("res://docs/qa/v120-ruins-boss/runtime-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t") + "\n"); file.close()
	print("RUINS_BOSS_RUNTIME checks=%d failures=%d" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
