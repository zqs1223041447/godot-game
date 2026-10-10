extends "res://tests/tornado_swift_test.gd"
## Reuse the paid purchase/ownership/Main cast and frozen-flight harness.
const HEAVY := "support:heavy_projectiles"
var timelines: Array = []
var hit_samples: Array = []
func support_definition_id() -> String: return HEAVY
func isolated_prefix() -> String: return "/tmp/godot-m1-tornado-heavy-"

func compile_checks() -> void:
	var old = load("/tmp/godot-tornado-heavy-baseline/skill_compiler.gd")
	for stats: Dictionary in [{"damage":26.0}, {"damage":26.0,"projectile_speed_increased":0.5,"attack_added_physical":5.0,"attack_added_fire":3.0}]:
		var snapshot := Combat.snapshot(stats,["return_on_range","explode_on_flight_end"])
		var before := var_to_bytes(snapshot)
		for skill: String in Compiler.Data.SKILLS:
			var selections: Array = [[]]
			for support: String in old.Supports.supports_for_skill(skill): selections.append([support])
			for selection: Array in selections:
				var previous: Dictionary = old.compile_group(skill,snapshot,selection)
				var current := Compiler.compile_group(skill,snapshot,selection)
				check(previous.ok and var_to_bytes(previous) == var_to_bytes(current),"Old/new full cast bytes: " + skill + str(selection))
				comparisons += 1
		for others: Array in [[],["swift_projectiles"],["volley","physical_focus","ignite","efficiency"],["focus","fire_focus","ember_proliferation","quickcast"]]:
			var selected := others + ["heavy_projectiles"]
			var plain := Compiler.compile_group("tornado",snapshot,others)
			var heavy := Compiler.compile_group("tornado",snapshot,selected)
			check(plain.ok and heavy.ok and not old.compile_group("tornado",snapshot,selected).ok,"Explicit former rejection now intentionally admitted")
			if not heavy.ok: continue
			selected.reverse()
			check(var_to_bytes(heavy) == var_to_bytes(Compiler.compile_group("tornado",snapshot,selected)),"Support order independent")
			near(heavy.mana,plain.mana*1.15,"Exact mana tradeoff")
			check(heavy.cooldown == plain.cooldown and heavy.initial_count == plain.initial_count and heavy.packets == plain.packets,"Raw damage types, amounts, count and cooldown unchanged")
			for role: String in ["parent","child"]:
				near(heavy.recipe[role].speed,plain.recipe[role].speed*0.75,"Final speed with source and swift factors: " + role)
				var unchanged: Dictionary = heavy.recipe[role].duplicate(true)
				for field: String in ["speed","base_speed"]:
					if plain.recipe[role].has(field): unchanged[field] = plain.recipe[role][field]
				check(unchanged == plain.recipe[role],"Range, lifetime, split and pierce unchanged")
			check(heavy.snapshot.tornado_recipe == heavy.recipe and heavy.snapshot.explosion_recipe == plain.snapshot.explosion_recipe,"Both role speeds freeze; independent explosion recipe unchanged")
			for role: String in plain.packets:
				var expected := Damage.resolve(plain.packets[role],plain.snapshot.modifiers)
				var actual := Damage.resolve(heavy.packets[role],heavy.snapshot.modifiers)
				for type: String in expected.components:
					near(actual.components[type],expected.components[type]*(1.0 if role == "secondary" else 1.2),"Typed role multiplier exactly once: " + role + "/" + type)
			if plain.has("burn_profile"):
				for role: String in plain.burn_profile.roles:
					near(heavy.burn_profile.roles[role].dps,plain.burn_profile.roles[role].dps*1.2,"Burn derives once from increased primary fire")
			if others.size() <= 1: trajectory(heavy)
		check(var_to_bytes(snapshot) == before,"Compilation leaves source intact")
	for id: String in ["pierce","lingering_chill","chain_extension","breadth"]:
		check(not Registry.compatibility_reason("tornado",[id]).is_empty(),"Unrelated incompatibility remains: " + id)

func trajectory(cast: Dictionary) -> void:
	var runtime := Runtime.new()
	var shots: Array[Dictionary] = []
	check(runtime.spawn_tornado(shots,Vector2.ZERO,Vector2.RIGHT,cast.snapshot,256,cast.initial_count) == cast.initial_count,"Existing runtime accepts compiled recipe")
	var events := runtime.advance(shots,2.5,[],Vector2.ZERO,256)
	var splits := 0; var returns := 0; var explosions := 0
	var return_times := {}; var ended := {}
	for event: Dictionary in events:
		match event.type:
			"split":
				splits += 1
				check(event.role == "parent","Only parents split, before any return")
				near(event.time,float(cast.recipe.parent.range)/float(cast.recipe.parent.speed),"Parent split time follows slower speed and same range")
			"return_started":
				returns += 1; return_times[event.projectile_id] = event.time
				check(event.role == "child","Parent split retains precedence over returning")
			"flight_ended": ended[event.projectile_id] = event.sequence
			"explosion":
				explosions += 1
				check(event.role == "child" and return_times.has(event.projectile_id) and ended.get(event.projectile_id,INF) < event.sequence,"Return then natural end then one child explosion")
				check(event.payload == cast.packets.secondary and not event.payload.tags.has("projectile"),"Explosion keeps independent typed payload and classification")
				near(event.age,float(cast.recipe.child.lifetime),"Return never resets child lifetime")
	check(shots.is_empty() and splits == cast.initial_count and returns == cast.initial_count*3 and explosions == returns,"Original split/return/explosion counts and final cleanup")
	timelines.append({"supports":cast.support_ids,"parent_speed":cast.recipe.parent.speed,"child_speed":cast.recipe.child.speed,"splits":splits,"returns":returns,"explosions":explosions})

func main_hit_checks() -> void:
	# Real Main settlement on a durable controlled enemy. No claim of natural
	# combat footage: zero armour/evasion isolates typed hit and shield effects.
	var target: Dictionary = arena._spawn_monster("crawler",arena.player_pos+Vector2(40,0),"ordinary","normal",[])
	target.spawn = 0.0; target.armour = 0.0; target.evasion = 0.0
	target.resistances = {"physical":0.25,"fire":0.5}
	var source := Combat.snapshot({"damage":26.0,"attack_added_physical":5.0,"attack_added_fire":3.0},["return_on_range","explode_on_flight_end"])
	var plain := Compiler.compile_group("tornado",source,[])
	var heavy := Compiler.compile_group("tornado",source,["heavy_projectiles"])
	for role: String in ["parent","child","secondary"]:
		var settled: Array = []
		for cast: Dictionary in [plain,heavy]:
			target.health = 10000.0; target.max_health = 10000.0; target.shield = 3.0
			arena.damage_trace.clear()
			arena._apply_damage_packet(target,cast.packets[role],cast.snapshot,Color.WHITE,0.0,{"cast_id":900,"projectile_id":901,"phase":role})
			check(arena.damage_trace.size() == 1,"Actual Main records one settled " + role + " hit")
			if arena.damage_trace.is_empty(): continue
			var record: Dictionary = arena.damage_trace.back()
			near(record.shield_spent,3.0,"Actual shield consumed before life")
			near(10000.0-float(target.health),float(record.health_lost),"Actual enemy life matches settlement")
			settled.append(record.duplicate(true))
		if settled.size() == 2:
			check(settled[0].tags == settled[1].tags,"Actual hit tags remain unchanged")
			for type: String in settled[0].components:
				near(settled[1].components[type],settled[0].components[type]*(1.0 if role == "secondary" else 1.2),"Actual Main component ratio: " + role + "/" + type)
			hit_samples.append({"role":role,"plain":settled[0].components,"heavy":settled[1].components})

func finish_swift() -> void:
	if is_instance_valid(arena) and not arena.projectiles.is_empty(): main_hit_checks()
	var report := {"checks":checks,"failures":failures,"old_new_cast_comparisons":comparisons,"carriers":carrier_evidence,"timelines":timelines,"main_hits":hit_samples,"evidence":evidence}
	FileAccess.open(OS.get_environment("HEAVY_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TORNADO_HEAVY checks=%d failures=%d comparisons=%d" % [checks,failures,comparisons])
	quit(1 if failures else 0)
