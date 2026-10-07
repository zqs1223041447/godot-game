extends SceneTree
## Bounded read-only native map export. No Main, save, fee, battle or art loading.
const Maps = preload("res://scripts/world/map_catalog.gd")
const Compiler = preload("res://scripts/world/map_compiler.gd")
const Bosses = preload("res://scripts/monsters/map_boss_profiles.gd")
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
const Session = preload("res://scripts/studies/modular_study_session.gd")
const Geometry = preload("res://scripts/studies/modular_study_geometry.gd")
const Routes = preload("res://scripts/studies/modular_study_routes.gd")
const Prepared = preload("res://scripts/world/prepared_map_entry.gd")
const Plan = preload("res://scripts/world/exploration_map_plan.gd")
const Runtime = preload("res://scripts/monsters/monster_runtime.gd")
const View = preload("res://scripts/visuals/world_view.gd")
const MAP_ID := "ruins_garden"
const SEED := 119001
const OUTPUT := "res://docs/qa/v119-reference/ruins-garden-fragment.json"
var checks := 0
var ticket: RefCounted


func require(value: bool, label: String) -> void:
	checks += 1
	if not value:
		push_error("Ruins reference: " + label)
		if ticket != null: ticket.finish_use(false)
		quit(1)
		assert(false, label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if OS.get_name() != "Windows":
		var isolated := OS.get_environment("XDG_DATA_HOME")
		require(isolated.begins_with("/tmp/") and OS.get_user_data_dir().begins_with(isolated + "/"), "Use isolated /tmp XDG directories")
	var bounds: Rect2 = View.exploration_arena()
	var original: Dictionary = Layout.layout(MAP_ID, bounds)
	var assembly: Dictionary = Session.layout(bounds, MAP_ID)
	require(original.ok and assembly.ok, "Native catalog assembly is available")
	var geometry := Geometry.new()
	ticket = Prepared.new()
	require(ticket.attach(geometry, Callable(geometry, "_release_native")), "Detached geometry ownership")
	var installed: Dictionary = geometry.install(bounds, assembly.polygons, original.landmarks.entry, assembly.presentation, MAP_ID)
	require(installed.ok, "Install original native contours")
	await physics_frame
	await physics_frame
	require(geometry.physics_ready(), "Native collision space synchronized")
	var routes: Dictionary = Routes.prepare(original.landmarks, geometry)
	require(routes.ok, "Production preparation validates both detours")
	require(original.landmarks.route_segments.size() == 12 and routes.landmarks.route_segments.size() == 14, "Twelve source connections become fourteen prepared legs")
	require(ticket.ready(routes.landmarks, bounds) and ticket.begin_use(PackedByteArray()).is_empty(), "Read-only Plan consumes prepared geometry")
	var tiers: Array[Dictionary] = []
	var options: Dictionary = Maps.options(false)
	for tier: int in range(1, 4):
		var compiled: Dictionary = Compiler.compile_normal(MAP_ID, tier, [], [])
		require(compiled.ok, "Compile formal tier %d" % tier)
		var eligible: Array[String] = []
		for special: Dictionary in options.special_modifiers:
			if Compiler.compile_normal(MAP_ID, tier, [], [special.id]).ok: eligible.append(special.id)
		var normal_ids: Array[String] = []
		for index: int in range(options.max_normal): normal_ids.append(options.normal_modifiers[index].id)
		var bonus: Dictionary = Compiler.compile_normal(MAP_ID, tier, normal_ids, [] if eligible.is_empty() else [eligible[0]])
		require(bonus.ok, "Compile legal maximum modifier bonus")
		tiers.append({"profile": compiled.profile, "eligible_special_ids": eligible,
			"maximum_modifier_bonus": bonus.profile.completion_reward - compiled.profile.completion_reward})
	var runtime := Runtime.new()
	var before := var_to_bytes([runtime.next_id, runtime.roots, runtime.queue, runtime.trace])
	var plan: Dictionary = Plan.plan(tiers[0].profile, runtime, SEED, bounds, Plan.LIVE_CAP, runtime.Catalog.CURRENT_ROLL_POLICY, {}, ticket)
	require(plan.ok, "Actual detached native Plan: " + str(plan.reason))
	require(var_to_bytes([runtime.next_id, runtime.roots, runtime.queue, runtime.trace]) == before, "Plan preserves caller runtime")
	require(plan.roots.size() == 25 and plan.ordinary_roots.size() == 24, "All 25 initial roots")
	require(plan.landmarks.outposts.size() == 6, "Six actual outposts")
	var shape: Dictionary = geometry.snapshot()
	require(shape.walls.is_empty() and shape.module_polygons.size() == 4, "Four native contours, no rectangular wall fallback")
	var vertex_count := 0
	for polygon: PackedVector2Array in shape.module_polygons: vertex_count += polygon.size()
	require(vertex_count <= Geometry.MAX_VERTICES, "Bounded native vertices")
	shape.landmarks = plan.landmarks
	var roots: Array[Dictionary] = []
	for enemy: Dictionary in plan.roots:
		require(enemy.generation == 0 and not enemy.exploration_awake and geometry.is_clear(enemy.pos, enemy.radius), "Native initial root is clear and dormant")
		roots.append({"actor_id": enemy.id, "root_id": enemy.root_id, "spawn_key": enemy.map_spawn_key,
			"template_id": enemy.template_id, "position": enemy.pos, "radius": enemy.radius,
			"generation": enemy.generation, "rarity": enemy.rarity, "reward_eligible": enemy.reward_eligible,
			"awake": enemy.exploration_awake, "outpost_id": enemy.get("map_outpost_id", "")})
	var test_available := false
	for item: Dictionary in Maps.options(true).maps:
		if item.id == MAP_ID: test_available = true
	require(not test_available, "Formal native map is absent from historical free-test options")
	var boss := Bosses.definition(Maps.MAPS[MAP_ID].boss_attack_id)
	require(boss.map_id == MAP_ID and Bosses.profile_reason(tiers[0].profile).is_empty(), "Own boss profile")
	var entry := {"id": MAP_ID, "name": Maps.MAPS[MAP_ID].name, "description": Layout.description(MAP_ID),
		"ordinary_target": Maps.MAPS[MAP_ID].ordinary_target, "native_entry": true, "test_available": test_available,
		"tiers": tiers, "boss_definition": boss, "geometry": shape,
		"plan_example": {"seed": SEED, "total": plan.roots.size(), "roots": roots,
			"spawn_records": plan.spawn_records, "mechanism_config": plan.mechanism_config, "optional_encounters": plan.optional_encounters},
		"native_reference": {"source_route_segments": original.landmarks.route_segments,
			"prepared_route_count": routes.landmarks.route_segments.size(), "contour_count": shape.module_polygons.size(),
			"vertex_count": vertex_count, "route_width": Routes.ROUTE_WIDTH, "detour_clearance_radius": Routes.CLEARANCE_RADIUS,
			"scope": "只读取正式目录并运行脱离角色的原生地形准备与单个I档Plan；不加载Main、不收费、不读写玩家存档、不运行战斗或渲染。",
			"evidence_path": "docs/qa/v119-reference/README.md"}}
	ticket.finish_use(false)
	require(not geometry.physics_ready() and not geometry._space.is_valid(), "Release isolated native physics space")
	var target := OUTPUT
	if not OS.get_cmdline_user_args().is_empty(): target = OS.get_cmdline_user_args()[0]
	var file := FileAccess.open(target, FileAccess.WRITE)
	require(file != null, "Open requested fragment output")
	file.store_string(JSON.stringify(clean({MAP_ID: entry}), "\t", true, true) + "\n")
	file.close()
	print("RUINS_REFERENCE checks=%d; 4 native contours, %d vertices, 25 roots, 6 outposts, 14 prepared route legs; no Main/save/fee/battle/art" % [checks, vertex_count])
	quit(0)


static func clean(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = clean(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result: Array = []
		for item: Variant in value: result.append(clean(item))
		return result
	if value is Vector2: return [value.x, value.y]
	if value is Rect2: return {"position": clean(value.position), "size": clean(value.size)}
	return value
