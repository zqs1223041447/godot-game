extends SceneTree
const Model = preload("res://scripts/build_state.gd")
const Data = preload("res://scripts/game_data.gd")
var checks: int = 0
var failures: int = 0
class CustomSnapshot extends BuildState:
	var bonus: float = 0.0
	func get_combat_snapshot() -> Dictionary:
		var value: Dictionary = super.get_combat_snapshot()
		value.base_damage += bonus
		return value
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)
func equivalence(model: BuildState) -> void:
	var saved: Dictionary = model._snapshot()
	model.stable_cache_enabled = false
	var expected_stats: Dictionary = model.get_stats()
	var expected_snapshot: Dictionary = model.get_combat_snapshot()
	var expected_casts: Dictionary = {}
	for id: String in Data.SKILLS: expected_casts[id] = model.get_skill_cast(id)
	model.stable_cache_enabled = true
	expect(model.get_stats() == expected_stats and model.get_combat_snapshot() == expected_snapshot, "Stable attribute/snapshot equals original uncached computation")
	for id: String in Data.SKILLS:
		expect(model.get_skill_cast(id) == expected_casts[id], "All skill packets/recipes equal uncached: " + id)
	expect(model._snapshot() == saved, "Cache never changes save payload")
func run() -> void:
	var model := Model.new()
	var cast: Dictionary = model.get_skill_cast("bolt")
	var first: Dictionary = model.cache_diagnostics()
	for unused: int in range(100):
		expect(model.get_skill_cast("bolt") == cast, "Repeated preview and cast selection are identical")
		model.get_stats()
		model.get_combat_snapshot()
	expect(model.cache_diagnostics() == first, "Stable repeats do not rebuild stats/snapshot/skill")
	model.xp += 1
	model.crafting.materials.calibration_shard += 1
	model.backpack_positions["item:swift_blade"] = Vector2i(0, 7)
	model.get_skill_cast("bolt")
	expect(model.cache_diagnostics() == first, "XP/wallet/bag movement do not recompile combat")
	model.level += 1
	model.get_skill_cast("bolt")
	expect(model.cache_diagnostics().revision == first.revision + 1, "Level invalidates stable inputs")
	equivalence(model)
	model.equipped.weapon = "prism_bow"
	equivalence(model)
	model.set_skill_supports("tornado", ["volley", "focus"])
	model.set_skill_supports("frost", ["heavy_projectiles", "lingering_chill"])
	model.set_skill_supports("nova", ["breadth", "concentrate"])
	model.set_skill_supports("chain", ["chain_extension", "chain_reach"])
	equivalence(model)
	var stable_bolt: Dictionary = model.get_skill_cast("bolt")
	var count: int = model.cache_diagnostics().skill_compiles
	model.skill_supports.bolt = ["focus"]
	expect(model.get_skill_cast("bolt") != stable_bolt and model.cache_diagnostics().skill_compiles == count + 1, "Direct nested support mutation invalidates only this skill")
	count = model.cache_diagnostics().skill_compiles
	model.get_skill_cast("nova")
	expect(model.cache_diagnostics().skill_compiles == count, "Other cached skills are retained after local link edit")
	equivalence(model)
	var rng := RandomNumberGenerator.new()
	rng.seed = 901
	var id: String = model.award_equipment(rng, 30, "rare", "local_weapon")
	expect(not id.is_empty() and model.equip(id), "Actual rolled equipment enters cache inputs")
	equivalence(model)
	var record: Dictionary = model.equipment_instances[id]
	var family: Dictionary = preload("res://scripts/items/equipment_catalog.gd").affix_definition(record.affixes[0].id)
	var tier: Dictionary = family.tiers[int(record.affixes[0].tier) - 1]
	record.affixes[0].value = int(tier.min) if int(record.affixes[0].value) != int(tier.min) else int(tier.max)
	equivalence(model)
	# Even legacy direct changes to passive inputs cannot serve an old result.
	var nodes: Dictionary = preload("res://scripts/passive_data.gd").get_nodes()
	for node_id: String in nodes:
		if node_id != "origin" and nodes[node_id].get("type", "") != "socket":
			model.allocated_nodes.append(node_id)
			break
	equivalence(model)
	cast = model.get_skill_cast("bolt")
	var immutable: Dictionary = cast.duplicate(true)
	cast.mana = 0.0
	cast.snapshot.base_damage = 9000.0
	var stats: Dictionary = model.get_stats()
	stats.damage = -9999.0
	expect(model.get_skill_cast("bolt") == immutable and model.get_stats().damage >= 0.0, "All returned nested views are detached")
	var first_token: PackedByteArray = model.get_build_view_token()
	model.skill_supports.bolt = ["volley"]
	expect(model.get_build_view_token() != first_token, "HUD view stamp observes link changes")
	var another := Model.new()
	expect(another.get_build_view_token() != Model.new().get_build_view_token(), "Replacing model cannot reuse another model's UI stamp")
	var custom := CustomSnapshot.new()
	var old: Dictionary = custom.get_skill_cast("bolt")
	custom.bonus = 12.0
	expect(not custom.cache_diagnostics().enabled and custom.get_skill_cast("bolt") != old, "Undeclared subclass dynamic overrides preserve original evaluation")
	expect(custom.get_build_view_token() != custom.get_build_view_token(), "Subclass HUD views are not incorrectly memoized")
	var before: Dictionary = model._snapshot()
	seed(8092)
	var expected_random: int = randi()
	seed(8092)
	model.get_stats(); model.get_combat_snapshot(); model.get_skill_cast("bolt")
	expect(randi() == expected_random and model._snapshot() == before, "Getters preserve RNG and persistent state")
	print("Stable build cache: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
