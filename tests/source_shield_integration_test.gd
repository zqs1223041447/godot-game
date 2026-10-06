extends SceneTree
## Bounded v76 integration against frozen 76c9cab. Never imports the project.
const Registry = preload("res://scripts/mechanics/mechanic_registry.gd")
const Source = preload("res://scripts/mechanics/source_monster_grants.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Parser = preload("res://scripts/passives/source_tree_runtime.gd")
const Catalog = preload("res://scripts/monsters/monster_catalog.gd")
const Supply = preload("res://scripts/monsters/source_shield_budget.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const Compiler = preload("res://scripts/encounters/encounter_compiler.gd")
const Encounter = preload("res://scripts/encounters/encounter_admission.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const Admission = preload("res://scripts/world/map_admission.gd")
const Camp = preload("res://scripts/world/map_camp_state.gd")
const Layout = preload("res://scripts/world/map_camp_layout.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const Telegraphs = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Frost = preload("res://scripts/combat/frost_lock_rules.gd")
const OldRegistry = preload("res://docs/qa/v076-integration-tests/frozen/registry.gd")
const OldSource = preload("res://docs/qa/v076-integration-tests/frozen/source.gd")
const OldCatalog = preload("res://docs/qa/v076-integration-tests/frozen/catalog.gd")
const OldCamp = preload("res://docs/qa/v076-integration-tests/frozen/camp_state.gd")
const OldRuntime = preload("res://docs/qa/v076-integration-tests/frozen/monster_runtime.gd")
const OldCompiler = preload("res://docs/qa/v076-integration-tests/frozen/encounter_compiler.gd")
const CAPACITY := "source_aegis_capacity"
const RECOVERY := "source_aegis_recovery"
const OLD_SOURCE_IDS: Array[String] = ["source_gale_stride", "source_ember_power", "source_grove_vitality"]
const SEEDS: Array[int] = [7, 73, 76076]
const WAVES: Array[int] = [1, 6, 15]
const SECTION_NAMES: Array[String] = ["registry", "sampling", "camps", "factory_maps", "snapshot_transactions", "cache_atomicity", "special_lineages", "main_adoption", "recharge_lifecycle"]
var checks: int = 0
var failures: int = 0
var sections: Dictionary = {}
var observations: Dictionary = {}
var completed: bool = false
var arena: Node

class TamperRuntime:
	extends "res://scripts/monsters/monster_runtime.gd"
	var corrupt: bool = true
	func create_root(template_id: String, wave: int, position: Vector2, context: String = "ordinary", rarity: String = "", mechanisms: Array = [], rewards: bool = true) -> Dictionary:
		var enemy: Dictionary = super.create_root(template_id, wave, position, context, rarity, mechanisms, rewards)
		if corrupt and not enemy.is_empty(): enemy.source_shield_profile.capacity_multiplier = 999.0
		return enemy
	func drain(available: int, bounds: Rect2) -> Array[Dictionary]:
		var enemies: Array[Dictionary] = super.drain(available, bounds)
		if corrupt and not enemies.is_empty(): enemies[0].source_shield_profile.capacity_multiplier = 999.0
		return enemies

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOURCE_SHIELD: " + label)
	return ok
func exact(actual: Variant, expected: Variant, label: String) -> bool:
	return check(var_to_bytes(actual) == var_to_bytes(expected), label)
func near(actual: float, expected: float, label: String) -> bool:
	return check(is_finite(actual) and absf(actual - expected) <= maxf(1e-8, absf(expected) * 1e-11), "%s actual=%s expected=%s" % [label, actual, expected])
func section(label: String) -> void:
	var before: int = checks
	var failed_before: int = failures
	completed = false
	call(label)
	check(completed, label + " reaches its final assertion without script exception")
	sections[label] = {"checks": checks - before, "failures": failures - failed_before}
	print("V076_SECTION " + label + " " + JSON.stringify(sections[label]))
func remapped(ids: Array) -> Array:
	var result: Array = ids.duplicate(true)
	for index: int in range(result.size()):
		if result[index] == "aegis_capacity": result[index] = CAPACITY
		elif result[index] == "aegis_recovery": result[index] = RECOVERY
	return result
func unchanged_fields(enemy: Dictionary) -> Dictionary:
	var result: Dictionary = enemy.duplicate(true)
	for key: String in ["shield", "max_shield", "shield_regen", "shield_recharge_rate", "shield_recharge_delay", "source_shield_profile", "mechanism_ids", "mechanism_stats", "mechanism_source_grants", "mechanism_policy"]: result.erase(key)
	return result
func saved_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func enemy_for(ids: Array, species: String = "crawler", wave: int = 6) -> Dictionary:
	return Catalog.make_enemy(1, species, wave, Vector2(500,400), "ordinary", "rare", ids)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-v076-"):
		push_error("Disposable v076 runner XDG fixture required"); quit(78); return
	var selected: PackedStringArray = OS.get_environment("V076_INTEGRATION_SECTIONS").split(",", false)
	for name: String in selected:
		if not SECTION_NAMES.has(name): push_error("Unknown integration section: " + name); quit(78); return
	for name: String in SECTION_NAMES:
		if not selected.is_empty() and not selected.has(name): continue
		if name in ["main_adoption", "recharge_lifecycle"] and arena == null:
			arena = load("res://scenes/main.tscn").instantiate()
			root.add_child(arena)
			arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
		section(name)
	var report: Dictionary = {"baseline_commit":"76c9cab", "checks":checks, "failures":failures, "sections":sections, "observations":observations,
		"seeds":SEEDS, "waves":WAVES, "rolls_per_seed_wave":12, "source_execution_version":Parser.CURRENT_SAVE_VERSION,
		"test_scope":"bounded source shield integration; no broad performance or full-history run"}
	var output: String = OS.get_environment("V076_INTEGRATION_REPORT")
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("Source shield integration: %d checks, %d failures" % [checks, failures])
	if arena != null: arena.free()
	quit(1 if failures else 0)

func registry() -> void:
	var old_ids: Array[String] = OldRegistry.get_ids()
	check(old_ids.size() == 26, "Frozen baseline contains 23 flat identities plus three source identities")
	var expected_ids: Array[String] = old_ids.duplicate()
	expected_ids.append(CAPACITY); expected_ids.append(RECOVERY)
	exact(Registry.get_ids(), expected_ids, "Only two new identities appended to the typed registry array")
	exact(Registry.MONSTER_STATS, OldRegistry.MONSTER_STATS, "Monster stat whitelist unchanged")
	for id: String in old_ids:
		exact(Registry.get_definition(id), OldRegistry.get_definition(id), "All prior definition bytes preserved: " + id)
		for actor: String in ["player", "monster"]:
			for coefficient: float in [0.0, 0.5, 1.0]:
				exact(Registry.resolve(id, actor, coefficient), OldRegistry.resolve(id, actor, coefficient), "Prior actor result bytes: %s/%s/%s" % [id,actor,coefficient])
	for alias: String in OldRegistry.ALIASES:
		for actor: String in ["player", "monster"]:
			exact(Registry.resolve(alias,actor), OldRegistry.resolve(alias,actor), "Alias result bytes " + alias + actor)
	for id: String in OLD_SOURCE_IDS:
		exact(Source.resolve(id), OldSource.resolve(id), "Prior three complete source return bytes " + id)
	var capacity_entry: Dictionary = Data.stat_entry("58218",0)
	var recovery_entries: Array = [Data.stat_entry("21929",1),Data.stat_entry("6949",1)]
	check(Parser.line_effect(capacity_entry.raw_line).grants==[{"stat":"max_shield","mode":"increased","value":0.08}],"Exact 58218:0 native grant")
	check(Parser.line_effect(recovery_entries[0].raw_line).grants==[{"stat":"max_shield","mode":"increased","value":0.04}],"Exact 21929:1 native grant")
	check(Parser.line_effect(recovery_entries[1].raw_line).grants==[{"stat":"shield_recharge_rate_increased","mode":"increased","value":0.10}],"Exact 6949:1 native grant")
	for id: String in [CAPACITY,RECOVERY]:
		check(Source.owns(id) and Registry.canonical_id(id)==id,"Exact typed admission " + id)
		check(not Registry.set_definition_stats(id,{"max_shield":999.0}),"Source identity cannot use legacy tuning " + id)
		var raw: Dictionary = Source.resolve(id)
		check(raw.ok and not raw.stats.has("max_shield") and not raw.stats.has("shield_regen"),"Source grants never invent monster flat bases " + id)
		if id==CAPACITY: exact(raw.definition.source_entry,capacity_entry,"Capacity provenance exact native entry")
		else:
			exact(raw.definition.source_entries,recovery_entries,"Atomic recovery provenance includes both exact entries")
			check(raw.definition.typed_grants.size()==2,"Recovery owns precisely two native typed grants")
		for actor: String in ["player","monster"]:
			for coefficient: float in [0.0,0.5,1.0]:
				var result: Dictionary = Registry.resolve(id,actor,coefficient)
				check(result.ok and not result.stats.has("max_shield") and not result.stats.has("shield_regen"),"Both actor grants retain typed percentages without supply")
				near(result.capacity_increased.max_shield,(0.08 if id==CAPACITY else 0.04)*coefficient,"Role coefficient scales native capacity")
				near(result.stats.get("shield_recharge_rate_increased",0.0),(0.0 if id==CAPACITY else 0.10)*coefficient,"Role coefficient scales native rate")
				check(not result.stats.has("shield_recharge_start_faster") and not result.stats.has("life_regen") and not result.stats.has("mana_regen"),"No faster start, Life or Mana behavior introduced")
	var pair: Dictionary = Registry.resolve_grants([CAPACITY,RECOVERY],"monster")
	near(pair.capacity_increased.max_shield,0.12,"Capacity increases add eight plus four percent")
	near(pair.stats.shield_recharge_rate_increased,0.10,"Recovery rate is ten percent increased")
	for ids: Array in [[CAPACITY,"poe_global_damage"],[RECOVERY,"unknown"]]:
		var refused: Dictionary = Registry.resolve_grants(ids,"monster")
		check(not refused.ok and refused.stats.is_empty() and refused.mechanism_ids.is_empty() and not refused.has("source_grants") and not refused.has("capacity_increased"),"Rejected mixed admission clears every grant atomically")
	completed=true

func sampling() -> void:
	exact(Catalog.AFFIX_POOL,OldCatalog.AFFIX_POOL,"Legacy affix pool bytes")
	exact(Catalog.STRIDE_AFFIX_POOL,OldCatalog.STRIDE_AFFIX_POOL,"v1 affix pool bytes")
	exact(Catalog.DAMAGE_LIFE_AFFIX_POOL,OldCatalog.CURRENT_AFFIX_POOL,"v2 affix pool bytes")
	exact(Catalog.CURRENT_AFFIX_POOL,remapped(OldCatalog.CURRENT_AFFIX_POOL),"v3 only remaps the two remaining Aegis entries")
	exact([Catalog.LEGACY_ROLL_POLICY,Catalog.STRIDE_ROLL_POLICY,Catalog.DAMAGE_LIFE_ROLL_POLICY,Catalog.CURRENT_ROLL_POLICY],["legacy_flat_v1","source_stride_v1","source_damage_life_v2","source_shield_v3"],"Four versioned policy identities")
	var seen: Dictionary = {CAPACITY:0,RECOVERY:0,"splitter":0,"brood_host":0}
	for seed_value: int in SEEDS:
		for wave: int in WAVES:
			var legacy: RandomNumberGenerator = RandomNumberGenerator.new(); legacy.seed=seed_value
			var old_legacy: RandomNumberGenerator = RandomNumberGenerator.new(); old_legacy.seed=seed_value
			var stride: RandomNumberGenerator = RandomNumberGenerator.new(); stride.seed=seed_value
			var old_stride: RandomNumberGenerator = RandomNumberGenerator.new(); old_stride.seed=seed_value
			var v2: RandomNumberGenerator = RandomNumberGenerator.new(); v2.seed=seed_value
			var old_v2: RandomNumberGenerator = RandomNumberGenerator.new(); old_v2.seed=seed_value
			var current: RandomNumberGenerator = RandomNumberGenerator.new(); current.seed=seed_value
			for index: int in range(12):
				exact([Catalog.ordinary_roll(legacy,wave),legacy.state],[OldCatalog.ordinary_roll(old_legacy,wave),old_legacy.state],"Legacy sampler and RNG exact")
				exact([Catalog.ordinary_roll_source_stride(stride,wave),stride.state],[OldCatalog.ordinary_roll_source_stride(old_stride,wave),old_stride.state],"v1 sampler and RNG exact")
				var old: Dictionary = OldCatalog.ordinary_roll_current(old_v2,wave)
				exact([Catalog.ordinary_roll_source_damage_life(v2,wave),v2.state],[old,old_v2.state],"Explicit v2 sampler and RNG exact")
				var expected: Dictionary = old.duplicate(true)
				if old.template in ["crawler","skitter","brute"]: expected.mechanisms=remapped(old.mechanisms)
				var actual: Dictionary = Catalog.ordinary_roll_current(current,wave)
				exact([actual,current.state],[expected,old_v2.state],"v3 sampler changes eligible IDs and preserves exact RNG")
				for id: String in [CAPACITY,RECOVERY]:
					if actual.mechanisms.has(id):seen[id]+=1
				if actual.template in ["splitter","brood_host"]:seen[actual.template]+=1
				var historical: Dictionary = OldCatalog.make_enemy(index+1,old.template,wave,Vector2(500,400),"ordinary",old.rarity,old.mechanisms)
				exact(Catalog.make_enemy(index+1,old.template,wave,Vector2(500,400),"ordinary",old.rarity,old.mechanisms),historical,"Unmigrated old factory dictionary bytes")
				var migrated: Dictionary = Catalog.make_enemy(index+1,actual.template,wave,Vector2(500,400),"ordinary",actual.rarity,actual.mechanisms)
				exact(unchanged_fields(migrated),unchanged_fields(historical),"v3 only changes shields and shield provenance")
	for key: String in seen:check(seen[key]>0,"Bounded seeded sampler covers "+key)
	observations.sampled=seen
	completed=true

func camps() -> void:
	var substitutions: int = 0
	for map_id: String in ["old_garden","broken_ruins","sunwell_terrace"]:
		var profile: Dictionary = Maps.compile(map_id,[],[]).profile
		var landmarks: Dictionary = Layout.layout(map_id,View.WORLD_ARENA).landmarks
		for seed_value: int in [7,73]:
			var current: RefCounted = Camp.new(); var old: RefCounted = OldCamp.new()
			check(current.begin(profile,landmarks,seed_value).ok and old.begin(profile,landmarks,seed_value).ok,"Default camps prepare")
			exact(current.checkpoint(),old.checkpoint(),"Default legacy camp full snapshot exact")
			for policy: String in [Catalog.LEGACY_ROLL_POLICY,Catalog.STRIDE_ROLL_POLICY,Catalog.DAMAGE_LIFE_ROLL_POLICY]:
				check(current.begin(profile,landmarks,seed_value,policy).ok and old.begin(profile,landmarks,seed_value,policy).ok,"Historical explicit camp policy accepted")
				exact(current.checkpoint(),old.checkpoint(),"Historical camp roster, positions, specials, source provenance exact "+policy)
			var expected: Dictionary = old.checkpoint()
			for camp: Dictionary in expected.camps:
				for row: Dictionary in camp.entries:
					if row.template_id not in ["splitter","brood_host","rift_warden"]:
						row.mechanisms=remapped(row.mechanisms)
						if row.mechanisms.has(CAPACITY) or row.mechanisms.has(RECOVERY):substitutions+=1
			check(current.begin(profile,landmarks,seed_value,Catalog.CURRENT_ROLL_POLICY).ok,"v3 camp policy accepted")
			exact(current.checkpoint(),expected,"v3 full camp snapshot changes only approved identities")
			var before: Dictionary = current.checkpoint()
			check(not current.begin(profile,landmarks,seed_value,"invalid").ok,"Unknown camp policy rejects")
			exact(current.checkpoint(),before,"Unknown policy cannot rewrite roster")
	check(substitutions>0,"Camp fixtures contain new shield identities")
	observations.camp_source_entries=substitutions
	completed=true

func factory_maps() -> void:
	var cases: Array[Dictionary] = [
		{"ids":[CAPACITY],"base":3.12,"increase":0.08,"max":3.3696,"rate":0.0},
		{"ids":[RECOVERY],"base":1.56,"increase":0.04,"max":1.6224,"rate":0.46475},
		{"ids":[CAPACITY,RECOVERY],"base":4.68,"increase":0.12,"max":5.2416,"rate":0.46475},
		{"ids":[CAPACITY,CAPACITY],"base":6.24,"increase":0.16,"max":7.2384,"rate":0.0},
	]
	for template: String in ["crawler","skitter","brute"]:
		for wave: int in WAVES:
			for row: Dictionary in cases:
				var enemy: Dictionary = enemy_for(row.ids,template,wave)
				check(not enemy.is_empty(),"Actual species/wave factory accepts selected supply")
				if enemy.is_empty():continue
				near(enemy.max_shield,row.max,"Species/wave independent authored supply times summed native increase")
				near(enemy.shield,row.max,"Factory begins with full shield")
				near(enemy.get("shield_recharge_rate",enemy.shield_regen),row.rate,"Actual final recharge rate")
				near(enemy.get("shield_recharge_delay",Defense.RECHARGE_BASE_DELAY),4.0,"Existing four second recharge delay")
				var snapshot: Dictionary = enemy.source_shield_profile
				exact(snapshot.keys(),Supply.PROFILE_KEYS,"Supply profile exposes complete auditable versioned shape")
				check(snapshot.budget_policy==Supply.POLICY and snapshot.supplies.size()==row.ids.size(),"Only selected exact new IDs contribute original budget")
				near(snapshot.base_max_shield,row.base,"Independent supply base is recorded")
				near(snapshot.capacity_increased,row.increase,"Native increases are added")
				near(snapshot.capacity_multiplier,1.0+float(row.increase),"Frozen multiplier is one plus summed increase")
				near(snapshot.legacy_base_shield,0.0,"No phantom historical flat base")
				near(snapshot.legacy_base_recharge_rate,0.0,"No phantom historical recharge base")
				check(Supply.snapshot_reason(enemy).is_empty(),"Actual generated profile validates independently")
				var base: Dictionary = OldCatalog.make_enemy(1,template,wave,Vector2(500,400),"ordinary","rare",[])
				exact(unchanged_fields(enemy),unchanged_fields(base),"Shield source leaves HP/damage/speed/rewards/species/wave unchanged")
				for order: Array in [["enemy_shield_from_health_20","enemy_max_health_120"],["enemy_max_health_120","enemy_shield_from_health_20"]]:
					var map: Dictionary = Maps.compile("old_garden",order,[]).profile
					var actual: Dictionary = Admission.create_root(Runtime.new(),map,template,wave,Vector2(500,400),"ordinary","rare",row.ids,true)
					check(actual.ok,"Actual map admission accepts source shield plus Strong")
					if actual.ok:
						near(actual.enemy.max_health,float(base.max_health)*1.20,"Strong changes health once")
						near(actual.enemy.max_shield,float(row.max)+float(base.max_health)*0.20*(1.0+float(row.increase)),"Map base uses pre-Strong canonical HP; only new base receives frozen increase")
						near(actual.enemy.shield,actual.enemy.max_shield,"Map addition updates current and max equally")
	var mixed: Dictionary = enemy_for(["aegis_capacity",RECOVERY])
	var legacy: Dictionary = Registry.resolve("aegis_capacity","monster").stats
	near(mixed.max_shield,(float(legacy.max_shield)+1.56)*1.04,"Historical flat shield is inside native capacity increase")
	near(mixed.source_shield_profile.legacy_base_shield,legacy.max_shield,"Historical base explicitly recorded")
	var mixed_rate: Dictionary = enemy_for(["aegis_recovery",RECOVERY])
	var legacy_rate: Dictionary = Registry.resolve("aegis_recovery","monster").stats
	near(mixed_rate.max_shield,(float(legacy_rate.get("max_shield",0.0))+1.56)*1.04,"Mixed historical recovery supplies its historical shield once")
	near(mixed_rate.shield_recharge_rate,(float(legacy_rate.shield_regen)+0.4225)*1.10,"Historical and authored recharge bases add before ten percent increase")
	near(mixed_rate.source_shield_profile.legacy_base_recharge_rate,legacy_rate.shield_regen,"Historical rate explicitly recorded")
	var partial: Dictionary = enemy_for([CAPACITY,RECOVERY])
	partial.shield=1.25;partial.health=float(partial.max_health)*0.40
	var before: PackedByteArray = var_to_bytes(partial)
	var profile: Dictionary = Compiler.compile(["enemy_shield_from_health_20","enemy_max_health_120"]).profile
	var applied: Dictionary = Compiler.apply_to_enemy(partial,profile)
	check(applied.ok,"Partial source shield admits map modifiers")
	near(applied.enemy.max_shield-applied.enemy.shield,float(partial.max_shield)-float(partial.shield),"Map addition preserves missing shield amount")
	near(applied.enemy.health,float(partial.health)*1.20,"Strong preserves missing-health fraction")
	exact(partial,bytes_to_var(before),"Map transform leaves complete canonical input unchanged")
	check(not Compiler.apply_to_enemy(applied.enemy,profile).ok,"Encounter marker rejects a second application")
	for ids: Array in [[],["aegis_capacity"],["aegis_recovery"],["source_grove_vitality"],["source_ember_power","aegis_capacity"]]:
		var old_enemy: Dictionary = OldCatalog.make_enemy(1,"crawler",6,Vector2(500,400),"ordinary","rare",ids)
		var current_enemy: Dictionary = enemy_for(ids)
		exact(current_enemy,old_enemy,"No new identity preserves complete old factory bytes")
		check(not current_enemy.has(Supply.FIELD),"No new identity has no source shield profile")
		exact(Compiler.apply_to_enemy(current_enemy,profile),OldCompiler.apply_to_enemy(old_enemy,profile),"No source shield profile preserves exact old map dictionary bytes")
	var line_a: String = Data._nodes["58218"].stats[0]
	var line_r: String = Data._nodes["21929"].stats[1]
	var line_rate: String = Data._nodes["6949"].stats[1]
	Data._nodes["58218"].stats[0]="0% increased maximum Energy Shield"
	Data._nodes["21929"].stats[1]="0% increased maximum Energy Shield"
	Data._nodes["6949"].stats[1]="0% increased Energy Shield Recharge Rate"
	var zero: Dictionary = enemy_for([CAPACITY,RECOVERY])
	Data._nodes["58218"].stats[0]=line_a;Data._nodes["21929"].stats[1]=line_r;Data._nodes["6949"].stats[1]=line_rate
	Source.resolve(CAPACITY);Source.resolve(RECOVERY)
	check(not zero.is_empty(),"Zero native increases are valid snapshots")
	if not zero.is_empty():
		near(zero.max_shield,4.68,"Zero native increase preserves independent base")
		near(zero.get("shield_recharge_rate",zero.shield_regen),0.4225,"Zero native rate preserves authored base rate")
		check(Supply.snapshot_reason(zero).is_empty(),"Zero snapshots validate")
	for bad: Variant in [-1.0,INF,NAN,"0.08"]:
		check(not Supply.build([CAPACITY],{}, {"max_shield":bad}).ok,"Budget rejects malformed capacity scalar")
	check(not Supply.build([CAPACITY],{"max_shield":1.7e308},{"max_shield":1.0}).ok,"Finite inputs overflowing capacity fail closed")
	observations.shield_arithmetic=cases
	completed=true

func snapshot_transactions() -> void:
	var canonical: Dictionary = enemy_for([CAPACITY,RECOVERY])
	var profile: Dictionary = Compiler.compile(["enemy_shield_from_health_20"]).profile
	var cached_before: PackedByteArray = var_to_bytes([Source._cache_keys,Source._cached_definitions])
	var line_a: String = Data._nodes["58218"].stats[0]
	var line_r: String = Data._nodes["21929"].stats[1]
	Data._nodes["58218"].stats[0]="80% increased maximum Energy Shield"
	Data._nodes["21929"].stats[1]="40% increased maximum Energy Shield"
	var applied: Dictionary = Compiler.apply_to_enemy(canonical,profile)
	exact([Source._cache_keys,Source._cached_definitions],bytes_to_var(cached_before),"Snapshot validator and map transform never invoke current Source.resolve")
	Data._nodes["58218"].stats[0]=line_a;Data._nodes["21929"].stats[1]=line_r
	check(applied.ok,"A live source change cannot invalidate previously spawned frozen input")
	near(applied.enemy.max_shield,5.2416+float(canonical.max_health)*0.20*1.12,"Map reads frozen I=12%, never changed live I=120%")
	var cases: Array[Dictionary] = []
	for key: String in ["budget_policy","supplies","legacy_base_shield","legacy_base_recharge_rate","base_max_shield","base_recharge_rate","capacity_increased","capacity_multiplier"]:
		var enemy: Dictionary = canonical.duplicate(true)
		enemy.source_shield_profile.erase(key);cases.append({"label":"missing "+key,"enemy":enemy})
	for key: String in ["legacy_base_shield","legacy_base_recharge_rate","base_max_shield","base_recharge_rate","capacity_increased","capacity_multiplier"]:
		for value: Variant in [NAN,INF,-1.0,"bad"]:
			var enemy: Dictionary = canonical.duplicate(true)
			enemy.source_shield_profile[key]=value;cases.append({"label":"invalid "+key,"enemy":enemy})
	for kind: String in ["policy","supply","multiplier","base","identity","grant_identity","mechanism_stats","missing_profile","capacity","maximum","rate","overflow"]:
		var enemy: Dictionary = canonical.duplicate(true)
		match kind:
			"policy":enemy.source_shield_profile.budget_policy="unknown"
			"supply":enemy.source_shield_profile.supplies[0].max_shield=999.0
			"multiplier":enemy.source_shield_profile.capacity_multiplier=1.08
			"base":enemy.source_shield_profile.base_recharge_rate=999.0
			"identity":enemy.mechanism_ids[0]="aegis_capacity"
			"grant_identity":enemy.mechanism_source_grants[0].id=RECOVERY
			"mechanism_stats":enemy.mechanism_stats.shield_recharge_rate_increased=0.90
			"missing_profile":enemy.erase(Supply.FIELD)
			"capacity":enemy.mechanism_source_grants[0].capacity_increased.max_shield=0.80
			"maximum":enemy.max_shield=99.0
			"rate":enemy.shield_recharge_rate=99.0
			"overflow":enemy.source_shield_profile.capacity_increased=1.7e308;enemy.source_shield_profile.capacity_multiplier=1.7e308
		cases.append({"label":kind,"enemy":enemy})
	for row: Dictionary in cases:
		var before: PackedByteArray = var_to_bytes(row.enemy)
		var rejected: Dictionary = Compiler.apply_to_enemy(row.enemy,profile)
		check(not rejected.ok and not rejected.has("enemy"),"Corrupt frozen snapshot rejects atomically: "+row.label)
		exact(row.enemy,bytes_to_var(before),"Rejected snapshot input preserved: "+row.label)
	var runtime: RefCounted = TamperRuntime.new()
	var before: Dictionary = Encounter._snapshot(runtime)
	var refused: Dictionary = Encounter.create_root(runtime,profile,"crawler",6,Vector2(500,400),"ordinary","rare",[CAPACITY,RECOVERY],true)
	check(not refused.ok,"Encounter detects corruption after actual root allocation")
	exact(Encounter._snapshot(runtime),before,"Invalid root restores IDs, roots, queue, trace completely")
	runtime.corrupt=false
	var root_enemy: Dictionary = runtime.create_root("splitter",6,Vector2(500,400))
	root_enemy.health=0.0;runtime.process_death(root_enemy)
	# Bounded fixture changes this runtime's child template only; production specials stay unchanged.
	runtime.templates.crawler.rarity="magic";runtime.templates.crawler.mechanisms=[CAPACITY]
	runtime.corrupt=true
	before=Encounter._snapshot(runtime)
	refused=Encounter.drain(runtime,profile,1,Rect2(0,0,1200,900))
	check(not refused.ok,"Encounter detects corrupt frozen descendant after queue consumption")
	exact(Encounter._snapshot(runtime),before,"Invalid descendant restores complete FIFO request and lineage/ID state")
	var overflow: Dictionary = canonical.duplicate(true)
	overflow.max_health=1.7e308;overflow.health=1.7e308
	var strong: Dictionary = Compiler.compile(["enemy_max_health_120"]).profile
	var bytes: PackedByteArray = var_to_bytes(overflow)
	check(not Compiler.apply_to_enemy(overflow,strong).ok,"Finite canonical health overflowing map transform rejects")
	exact(overflow,bytes_to_var(bytes),"Post-map overflow leaves original actor intact")
	observations.snapshot_tamper_fixtures=cases.size()
	completed=true

func cache_atomicity() -> void:
	for id: String in Source.IDS:Source.resolve(id)
	check(Source._cache_keys.size()==5 and Source._cached_definitions.size()==5,"Exactly five independently cached source identities")
	var old_bytes: Dictionary = {}
	for id: String in OLD_SOURCE_IDS:old_bytes[id]=var_to_bytes(Source.resolve(id))
	var existing: Dictionary = enemy_for([CAPACITY,RECOVERY])
	var existing_bytes: PackedByteArray = var_to_bytes(existing)
	var line: String = Data._nodes["58218"].stats[0]
	Data._nodes["58218"].stats[0]="16% increased maximum Energy Shield"
	var changed: Dictionary = enemy_for([CAPACITY,RECOVERY])
	Data._nodes["58218"].stats[0]=line;Source.resolve(CAPACITY)
	near(changed.max_shield,4.68*1.20,"Live native update affects only new factory output")
	exact(existing,bytes_to_var(existing_bytes),"Live native update never changes existing frozen actor")
	for entry: Array in [["58218",0,CAPACITY],["21929",1,RECOVERY],["6949",1,RECOVERY]]:
		var saved: String = Data._nodes[entry[0]].stats[entry[1]]
		var runtime: RefCounted = Runtime.new()
		var profile: Dictionary = Maps.compile("old_garden",["enemy_shield_from_health_20"],[]).profile
		var before: Dictionary = Encounter._snapshot(runtime)
		Data._nodes[entry[0]].stats[entry[1]]="4% increased Armour"
		var raw: Dictionary = Source.resolve(entry[2])
		var bundle: Dictionary = Registry.resolve_grants([CAPACITY,RECOVERY],"monster")
		var factory: Dictionary = enemy_for([CAPACITY,RECOVERY])
		var admitted: Dictionary = Admission.create_root(runtime,profile,"crawler",6,Vector2(500,400),"ordinary","rare",[CAPACITY,RECOVERY],true)
		var after: Dictionary = Encounter._snapshot(runtime)
		Data._nodes[entry[0]].stats[entry[1]]=saved
		var restored: Dictionary = Source.resolve(entry[2])
		check(not raw.ok and raw.stats.is_empty() and raw.definition.is_empty() and not raw.has("capacity_increased"),"Bad single/bundle member cannot return cached partial success")
		check(not bundle.ok and bundle.stats.is_empty() and bundle.mechanism_ids.is_empty() and not bundle.has("source_grants") and not bundle.has("capacity_increased"),"Either invalid recovery member clears entire mixed admission")
		check(factory.is_empty() and not admitted.ok and restored.ok,"Malformed source blocks actual factory/map; restoration succeeds")
		exact(after,before,"Bad source restores allocated IDs and full runtime state")
		for id: String in OLD_SOURCE_IDS:exact(Source.resolve(id),bytes_to_var(old_bytes[id]),"New identity failure preserves old cache/return bytes "+id)
		check(Source._cache_keys.size()<=5 and Source._cached_definitions.size()<=5,"Caches remain bounded after each alternating failure")
	for id: String in Source.IDS:Source.resolve(id)
	check(Source._cache_keys.size()==5 and Source._cached_definitions.size()==5,"All five cached entries recover after alternating source failures")
	completed=true
func clean_main() -> void:
	arena._world_mode = "normal"; arena.enemies.clear(); arena.monster_runtime = Runtime.new()
	arena._geometry.configure("normal", arena.ARENA); arena.freeze_runtime.reset(); arena.telegraphs = Telegraphs.new()
	arena.burn_runtime.reset(); arena.shock_runtime.reset(); arena.feedback_runtime.reset()
	arena.incoming_damage_trace.clear(); arena.burn_trace.clear(); arena.telegraph_trace.clear(); arena.event_counts.clear()
	arena._burn_incoming_time = -1.0; arena._burn_immunity_until = 0.0
	arena.alive = true; arena.elapsed = 0.0; arena._burn_step_active = false
	arena.player_pos = Vector2(900,400); arena.spawn_timer = 1000.0; arena.auto_fire = false
	arena._clear_encounter()
	arena.rng.seed = 76076; arena.ordinary_admissions = 0; arena.demo_mode = false
	arena.invulnerable = 0.0; arena.damage_delay = 0.0
	arena._stats = arena.state.get_stats()
	for field: String in ["armour", "evasion", "fire_resistance", "life_regen", "shield_regen", "shield_recharge_rate"]: arena._stats[field] = 0.0
	arena.health = 10000.0; arena.shield = 0.0; arena._stats.max_health = 10000.0
	arena.hud.close_panel()
func main_observation() -> PackedByteArray:
	return var_to_bytes([arena.state.snapshot(), arena.state.successful_saves, saved_bytes(arena.build_save_path), arena.rng.state, Encounter._snapshot(arena.monster_runtime), arena.enemies, arena._map_camps.checkpoint(), arena._map_run.admitted, arena.rings])
func source_seed(id: String) -> int:
	for candidate: int in range(1,129):
		var rng := RandomNumberGenerator.new(); rng.seed = candidate
		if Catalog.ordinary_roll_current(rng,6).mechanisms.has(id): return candidate
	return -1


func special_lineages() -> void:
	exact(Catalog.TEMPLATES, OldCatalog.TEMPLATES, "All authored templates including specials and death children remain unchanged")
	for template: String in ["splitter", "brood_host", "rift_warden", "ember_guard", "frost_guard", "storm_skitter", "mist_skitter"]:
		var context := "level_boss" if template == "rift_warden" else "ordinary"
		exact(Catalog.make_enemy(1, template, 6, Vector2(500,400), context), OldCatalog.make_enemy(1, template, 6, Vector2(500,400), context), "Natural special/boss factory bytes " + template)
	for template: String in ["splitter", "brood_host", "rift_warden"]:
		var current := Runtime.new(); var frozen := OldRuntime.new()
		var context := "level_boss" if template == "rift_warden" else "ordinary"
		var root_now: Dictionary = current.create_root(template, 6, Vector2(500,400), context)
		var root_old: Dictionary = frozen.create_root(template, 6, Vector2(500,400), context)
		root_now.health = 0.0; root_old.health = 0.0
		exact(current.process_death(root_now), frozen.process_death(root_old), "Special root death accounting remains frozen " + template)
		var children: Array[Dictionary] = current.drain(6, Rect2(0,0,1200,900))
		var old_children: Array[Dictionary] = frozen.drain(6, Rect2(0,0,1200,900))
		exact(children, old_children, "Actual death descendants retain historical IDs and full factory bytes " + template)
		exact(Encounter._snapshot(current), Encounter._snapshot(frozen), "Complete special lineage roots, FIFO queue, IDs and trace remain frozen " + template)
		for child: Dictionary in children:
			check(not child.mechanism_ids.has(CAPACITY) and not child.mechanism_ids.has(RECOVERY), "Source shield never migrate into authored death children")
	completed = true


func main_adoption() -> void:
	clean_main();arena.wave=6
	var canonical: Dictionary = arena.state.snapshot()
	var disk: PackedByteArray = saved_bytes(arena.build_save_path)
	var saves: int = arena.state.successful_saves
	var seeds: Dictionary = {}
	for id: String in [CAPACITY,RECOVERY]:
		clean_main();arena.wave=6
		var seed_value: int = source_seed(id);seeds[id]=seed_value
		check(seed_value>0,"Bounded seed fixture finds current shield identity "+id)
		var expected_rng: RandomNumberGenerator = RandomNumberGenerator.new();expected_rng.seed=seed_value
		var expected: Dictionary = Catalog.ordinary_roll_current(expected_rng,6)
		arena.rng.seed=seed_value
		var enemy: Dictionary = arena._spawn_enemy(Vector2(500,400))
		check(not enemy.is_empty() and enemy.mechanism_ids==expected.mechanisms and enemy.mechanism_ids.has(id),"Main default spawn uses current v3 shield identity "+id)
		check(arena.rng.state==expected_rng.state,"Main forced-position sampler RNG state exact")
		check(enemy.has(Supply.FIELD),"Main natural source actor carries independent shield supply profile")
		clean_main();arena.wave=6;arena.rng.seed=seed_value
		var natural: Dictionary = arena._spawn_enemy()
		check(not natural.is_empty() and natural.mechanism_ids.has(id) and arena.ordinary_admissions==1,"Actual unforced Main spawn adopts v3 shield source")
	var profile: Dictionary = Maps.compile("old_garden",[],[]).profile
	var camp_seed: int = -1
	var landmarks: Dictionary = Layout.layout(profile.id,arena.ARENA).landmarks
	for candidate: int in range(1,33):
		var seed_text: String = JSON.stringify([candidate,1,profile.id,profile.get("journey_tier",0),"map-camps-v1"])
		var derived_seed: int = seed_text.sha256_text().substr(0,15).hex_to_int()
		var fixture: RefCounted = Camp.new()
		fixture.begin(profile,landmarks,derived_seed,Catalog.CURRENT_ROLL_POLICY)
		var found_capacity: bool = false
		var found_recovery: bool = false
		for camp: Dictionary in fixture.checkpoint().camps:
			for row: Dictionary in camp.entries:
				found_capacity=found_capacity or row.mechanisms.has(CAPACITY)
				found_recovery=found_recovery or row.mechanisms.has(RECOVERY)
		if found_capacity and found_recovery:camp_seed=candidate;break
	check(camp_seed>0,"Bounded Main camp seed includes both selected shield sources")
	arena.rng.seed=camp_seed
	seeds.camp_rng_seed=camp_seed
	var before: PackedByteArray = main_observation()
	var prepared: Dictionary = arena._prepare_camp_run(profile,1)
	check(prepared.ok,"Main current camp preflight succeeds")
	if prepared.ok:
		var frozen: Dictionary = prepared.state.checkpoint()
		var manual: RefCounted = Camp.new();manual.begin(profile,prepared.landmarks,frozen.seed,Catalog.CURRENT_ROLL_POLICY)
		exact(frozen,manual.checkpoint(),"Actual Main current camp preflight freezes v3 policy")
		var found: int = 0
		for camp: Dictionary in frozen.camps:
			for row: Dictionary in camp.entries:
				if row.mechanisms.has(CAPACITY) or row.mechanisms.has(RECOVERY):found+=1
		check(found>0,"Main current camp roster exercises source shield identities")
	exact(main_observation(),before,"Successful preflight preserves RNG, runtime, canonical build and disk")
	for entry: Array in [["58218",0,CAPACITY],["21929",1,RECOVERY],["6949",1,RECOVERY]]:
		var line: String = Data._nodes[entry[0]].stats[entry[1]]
		Data._nodes[entry[0]].stats[entry[1]]="unsupported source fixture"
		var refused: Dictionary = arena._prepare_camp_run(profile,1)
		Data._nodes[entry[0]].stats[entry[1]]=line;Source.resolve(entry[2])
		check(not refused.ok,"Main rejects current source preflight for each atomic member")
		exact(main_observation(),before,"Rejected preflight preserves all runtime and save bytes")
	exact(arena.state.snapshot(),canonical,"Main integration preserves complete canonical schema47 state")
	exact(saved_bytes(arena.build_save_path),disk,"Main integration preserves save bytes")
	check(arena.state.successful_saves==saves and canonical.version==47 and Parser.CURRENT_SAVE_VERSION==45,"No save write or schema/execution migration")
	observations.actual_main_seeds=seeds
	completed=true

func main_enemy(ids: Array) -> Dictionary:
	clean_main();arena.wave=6
	var enemy: Dictionary = arena._spawn_monster("crawler",Vector2(200,200),"ordinary","rare",ids,false)
	enemy.spawn=0.0;enemy.speed=0.0;enemy.attack_timer=100.0
	return enemy
func tick(delta: float) -> void:
	arena.elapsed+=delta
	arena._update_enemies(delta)
func recharge_lifecycle() -> void:
	var enemy: Dictionary = main_enemy([CAPACITY,RECOVERY])
	var canonical: Dictionary = arena.state.snapshot()
	var disk: PackedByteArray = saved_bytes(arena.build_save_path)
	var packet: Dictionary = Damage.packet({"physical":0.5},["hit","spell"],"bolt")
	var original: float = enemy.shield
	arena._apply_damage_packet(enemy,packet,{},Color.WHITE)
	near(enemy.shield,original-0.5,"Actual Main hit consumes shield")
	near(enemy.damage_delay,4.0,"Actual Main positive hit starts exact four second delay")
	tick(3.75)
	near(enemy.shield,original-0.5,"No recovery before delay expires")
	near(enemy.damage_delay,0.25,"Global time counts down recharge delay")
	tick(0.5)
	near(enemy.shield,original-0.5+0.46475*0.25,"Frame crossing uses only residual quarter-second for recharge")
	near(enemy.damage_delay,0.0,"Crossing clamps remaining wait to zero")
	arena._apply_damage_packet(enemy,packet,{},Color.WHITE)
	near(enemy.damage_delay,4.0,"A later positive hit restarts the full delay")
	tick(0.75)
	var partial_delay: float = enemy.damage_delay
	var partial_shield: float = enemy.shield
	arena._apply_damage_packet(enemy,Damage.packet({"physical":0.0},["hit","spell"],"bolt"),{},Color.WHITE)
	near(enemy.damage_delay,partial_delay,"Actual zero damage packet does not reset wait")
	near(enemy.shield,partial_shield,"Actual zero damage packet does not consume shield")
	enemy.evasion=1000000000.0;enemy.evasion_entropy=0.0
	var hits_before: int = arena.attack_admission_trace.size()
	arena._apply_damage_packet(enemy,Damage.packet({"physical":1.0},["hit","attack"],"tornado"),{"accuracy":1.0},Color.WHITE)
	check(arena.attack_admission_trace.size()==hits_before+1 and not arena.attack_admission_trace.back().hit,"Actual Main evasion rejects targeted attack")
	near(enemy.damage_delay,partial_delay,"Evaded hit does not reset delay")
	near(enemy.shield,partial_shield,"Evaded hit leaves shield unchanged")
	enemy.damage_delay=0.05;enemy.shield=float(enemy.max_shield)-0.01
	tick(1.0)
	near(enemy.shield,enemy.max_shield,"Long residual recharge clamps at maximum")
	enemy.health=0.0;enemy.shield=0.0;enemy.damage_delay=0.0
	tick(2.0)
	near(enemy.shield,0.0,"Dead actor cannot recharge or resurrect")

	enemy=main_enemy([RECOVERY])
	var burned_from: float = enemy.shield
	var attached: Dictionary = arena.burn_runtime.apply("monster",int(enemy.id),0,0.2,1.0,0.0,{"skill_id":"meteor","cast_id":1,"phase":"direct"})
	check(attached.ok,"Actual burn runtime attaches bounded monster burn")
	arena.elapsed=0.25;arena._advance_monster_burn(enemy,0.25)
	near(enemy.shield,burned_from-0.05,"Actual burn segment consumes shield")
	near(enemy.damage_delay,4.0,"Actual positive burn settlement resets four second delay")
	tick(0.25)
	near(enemy.damage_delay,3.75,"Burn-free update advances global delay")
	arena._advance_monster_burn(enemy,0.5)
	near(enemy.damage_delay,4.0,"Next actual positive burn segment resets full delay again")
	var delay_before: float = enemy.damage_delay
	arena._advance_monster_burn(enemy,0.5)
	near(enemy.damage_delay,delay_before,"Zero-duration burn advance causes no reset")
	check(arena.burn_trace.size()==2,"Only two positive elapsed burn segments settled")

	for ids: Array in [[CAPACITY],[]]:
		enemy=main_enemy(ids)
		if ids.is_empty():
			var mapped: Dictionary = Compiler.apply_to_enemy(enemy,Compiler.compile(["enemy_shield_from_health_20"]).profile)
			check(mapped.ok,"Map-only actor receives shield base")
			enemy=mapped.enemy;arena.enemies.clear();arena.enemies.append(enemy)
		enemy.shield=0.0;enemy.damage_delay=0.0
		tick(5.0)
		near(enemy.shield,0.0,"Capacity-only or map-only shield never invents recharge rate")
		near(enemy.get("shield_recharge_rate",enemy.shield_regen),0.0,"No recovery affix leaves actual rate zero")

	enemy=main_enemy([RECOVERY]);enemy.shield=0.0;enemy.damage_delay=0.10
	var position: Vector2 = enemy.pos
	var attack_timer: float = enemy.attack_timer
	var frozen: Dictionary = arena.freeze_runtime.apply(int(enemy.id),str(enemy.rarity),0.0,Frost.PLAYER_POLICY,{"skill_id":"frost","phase":"direct"})
	check(frozen.ok and frozen.applied,"Existing freeze runtime admits normal frozen actor")
	tick(0.20)
	near(enemy.damage_delay,0.0,"Existing freeze does not pause global recharge wait")
	near(enemy.shield,0.46475*0.10,"Existing freeze preserves global partial-frame recharge")
	exact(enemy.pos,position,"Frozen movement clock remains paused")
	near(enemy.attack_timer,attack_timer,"Frozen attack clock remains paused")
	exact(arena.state.snapshot(),canonical,"Damage, burn, recharge and freeze preserve canonical build")
	exact(saved_bytes(arena.build_save_path),disk,"Combat integration leaves save bytes unchanged")
	observations.actual_recharge={"capacity_only":3.3696,"recovery_only":1.6224,"paired":5.2416,"rate":0.46475,"delay":4.0,"crossing_residual":0.25,"freeze_uses_global_delta":true}
	completed=true
