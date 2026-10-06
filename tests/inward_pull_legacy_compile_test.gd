extends SceneTree
## Reuse the committed v066 oracle, without re-running its frozen producer.
const Registry = preload("res://scripts/combat/support_registry.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const ORACLE: String = "res://docs/qa/v066-runtime/legacy-support-after.json"
const ORACLE_SHA256: String = "3c8262b7111eaf883b1931496ad55283118c994ea0967448b57702796eddb0de"
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if FileAccess.get_sha256(ORACLE) != ORACLE_SHA256:
		_fail("Committed legacy oracle hash changed")
		quit(1)
		return
	var oracle: Variant = JSON.parse_string(FileAccess.get_file_as_string(ORACLE))
	if not oracle is Dictionary or not oracle.get("rows") is Array or oracle.rows.size() != 783:
		_fail("Committed legacy oracle shape changed")
		quit(1)
		return
	seed(660065)
	var rows: Array = []
	for row: Dictionary in oracle.rows:
		var stats: Dictionary = {"damage": 100.0}
		if int(row.config) > 0:
			stats.merge({"spell_added_cold": 13.0, "spell_added_lightning": 11.0, "attack_added_physical": 7.0,
				"global_increased": 0.2, "area_increased": 0.1, "spell_increased": 0.3,
				"area_size_increased": 0.25, "mana_cost_efficiency_increased": 0.25,
				"crit_base_chance": 0.5, "crit_base_multiplier": 2.0, "fire_dot_multiplier": 0.2, "burn_faster": 0.25})
		if int(row.config) == 2: stats.resolute_technique = 1.0
		var snapshot: Dictionary = Combat.snapshot(stats, ["return_on_range", "explode_on_flight_end"])
		var compiled: Dictionary = Compiler.compile_group(row.skill, snapshot, row.links)
		if not compiled.ok:
			_fail("Old selection no longer compiles: " + str(row))
			continue
		var actual: Dictionary = {"skill": row.skill, "config": int(row.config), "links": row.links,
			"compiled": _hash(compiled), "program": _hash(Registry.compile_programs(row.skill, row.links, 5))}
		if actual.compiled != row.compiled or actual.program != row.program:
			_fail("Old compiled/program bytes changed: " + row.skill + " " + str(row.links))
		rows.append(actual)
	var actual: Dictionary = {"rows": rows, "global_rng": [randi(), randi(), randi()]}
	var encoded: String = JSON.stringify(actual)
	if encoded != FileAccess.get_file_as_string(ORACLE): _fail("Current output JSON/RNG bytes differ from committed oracle")
	print("Inward pull legacy compiler: %d frozen rows, %d failures; exact JSON, compiled/program byte hashes and global RNG" % [rows.size(), failures])
	quit(1 if failures else 0)


func _fail(label: String) -> void:
	failures += 1
	push_error("FAIL: " + label)


static func _hash(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()
