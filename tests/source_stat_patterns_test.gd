extends SceneTree
## Source-backed parser contract. Passing here measures parsing only, not stat execution.

const Parser = preload("res://scripts/passives/source_stat_patterns.gd")
const SOURCE_PATH: String = "res://data/passive_source/data.json"
const SOURCE_MANIFEST_PATH: String = "res://data/passive_source/source_manifest.json"
const POSITIVE_CASES: Array[Dictionary] = [
	{"node_id": "35448", "stat": "max_health", "value": 100.0, "mode": "flat"},
	{"node_id": "35724", "stat": "max_mana", "value": 10.0, "mode": "flat"},
	{"node_id": "27929", "stat": "max_shield", "value": 20.0, "mode": "flat"},
	{"node_id": "49254", "stat": "global_increased", "value": 0.15, "mode": "increased"},
	{"node_id": "62103", "stat": "projectile_increased", "value": 0.10, "mode": "increased"},
	{"node_id": "54694", "stat": "spell_increased", "value": 0.20, "mode": "increased"},
	{"node_id": "14996", "stat": "fire_increased", "value": 0.10, "mode": "increased"},
	{"node_id": "34977", "stat": "cold_increased", "value": 0.25, "mode": "increased"},
	{"node_id": "35069", "stat": "lightning_increased", "value": 0.25, "mode": "increased"},
	{"node_id": "43193", "stat": "elemental_increased", "value": 0.10, "mode": "increased"},
	{"node_id": "59728", "stat": "area_increased", "value": 0.10, "mode": "increased"},
	{"node_id": "63673", "stat": "attack_speed_increased", "value": 0.05, "mode": "increased"},
	{"node_id": "63417", "stat": "move_speed_increased", "value": 0.04, "mode": "increased"},
	{"node_id": "44797", "stat": "mana_regen_increased", "value": 0.20, "mode": "increased"},
	{"node_id": "48836", "stat": "max_health", "value": 0.08, "mode": "increased"},
	{"node_id": "29994", "stat": "max_mana", "value": 0.08, "mode": "increased"},
	{"node_id": "32992", "stat": "max_shield", "value": 0.05, "mode": "increased"},
]
const SOURCE_REJECTIONS: Array[Dictionary] = [
	{"node_id": "25738", "marker": "recently"},
	{"node_id": "45945", "marker": "while"},
	{"node_id": "46344", "marker": "bows"},
	{"node_id": "32169", "marker": "damage over time"},
	{"node_id": "41387", "marker": "minions"},
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_MANIFEST_PATH))
	_expect(manifest is Dictionary, "Source manifest loads")
	if manifest is Dictionary:
		var pin: Variant = manifest.get("source", {})
		_expect(pin is Dictionary and pin.get("version") == "3.29.1"
			and pin.get("commit") == "8bd138b32ea2631455cac5935bfab089f826094f"
			and pin.get("sha256") == "7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122",
			"Examples are read from the pinned 3.29.1 source manifest")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	_expect(parsed is Dictionary, "Pinned 3.29.1 source JSON loads")
	if not parsed is Dictionary:
		print("Source stat patterns: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var nodes: Dictionary = parsed.get("nodes", {})
	_check_positive_examples(nodes)
	_check_source_rejections(nodes)
	_check_synthetic_rejections()
	print("Source stat patterns: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)


func _check_positive_examples(nodes: Dictionary) -> void:
	for example: Dictionary in POSITIVE_CASES:
		var node: Variant = nodes.get(str(example.node_id), {})
		_expect(node is Dictionary, "Pinned source contains positive example node " + str(example.node_id))
		if not node is Dictionary:
			continue
		var lines: Variant = node.get("stats", [])
		_expect(lines is Array, "Pinned node retains source stats array: " + str(example.node_id))
		if not lines is Array:
			continue
		var source_match_found: bool = false
		for source_line: Variant in lines:
			if not source_line is String:
				continue
			var unchanged: String = source_line
			var result: Dictionary = Parser.parse_line(source_line)
			if result.get("supported") != true or not result.get("grants") is Array or result.grants.size() != 1:
				continue
			var grant: Dictionary = result.grants[0]
			if grant.get("stat") != example.stat or grant.get("mode") != example.mode:
				continue
			_near(float(grant.get("value", NAN)), float(example.value), "Source value is retained/normalized for node " + str(example.node_id))
			_expect(result.size() == 3 and result.get("reason") == "", "Supported result has the exact shape for node " + str(example.node_id))
			_expect(grant.size() == 3, "Grant has the exact stat/value/mode shape for node " + str(example.node_id))
			_expect(source_line == unchanged, "Parser leaves source input unchanged for node " + str(example.node_id))
			source_match_found = true
			break
		_expect(source_match_found, "An actual source line parses to the expected tag/value/mode at node " + str(example.node_id))


func _check_source_rejections(nodes: Dictionary) -> void:
	for example: Dictionary in SOURCE_REJECTIONS:
		var node: Variant = nodes.get(str(example.node_id), {})
		_expect(node is Dictionary, "Pinned source contains rejection example node " + str(example.node_id))
		if not node is Dictionary:
			continue
		var lines: Variant = node.get("stats", [])
		_expect(lines is Array, "Pinned rejection node retains source stats array: " + str(example.node_id))
		if not lines is Array:
			continue
		var source_rejection_found: bool = false
		for source_line: Variant in lines:
			if not source_line is String or not str(source_line).to_lower().contains(str(example.marker)):
				continue
			var unchanged: String = source_line
			_expect_rejected(Parser.parse_line(source_line), "source node " + str(example.node_id) + " / " + str(example.marker))
			_expect(source_line == unchanged, "Parser leaves rejected source input unchanged at node " + str(example.node_id))
			source_rejection_found = true
			break
		_expect(source_rejection_found, "Pinned source contains a rejected example at node " + str(example.node_id))


func _check_synthetic_rejections() -> void:
	var rejected_lines: Array[String] = [
		"-5 to maximum Life",
		"-8% increased Attack Speed",
		"10% increased Damage.",
		"10% increased Damage\n5% increased Attack Speed",
		"10% increased Chaos Damage while Poisoned",
		"+10% increased Damage",
	]
	for line: String in rejected_lines:
		var unchanged: String = line
		_expect_rejected(Parser.parse_line(line), line)
		_expect(line == unchanged, "Parser leaves synthetic rejected input unchanged: " + line)
	var negative: Dictionary = Parser.parse_line("-5 to maximum Life")
	_expect(str(negative.reason).contains("负值"), "A complete negative form receives an explicit negative-value reason")
	var multiline: Dictionary = Parser.parse_line("10% increased Damage\n5% increased Attack Speed")
	_expect(str(multiline.reason).contains("多行"), "A two-line input receives an explicit multiline reason")
	_expect_rejected(Parser.parse_line("  "), "whitespace-only line")
	_expect_rejected(Parser.parse_line(42), "non-string input")
	_check_decimal_values()


func _check_decimal_values() -> void:
	var flat: Dictionary = Parser.parse_line("+12.5 to maximum Life")
	_expect(flat.get("supported") == true and flat.get("grants") is Array and flat.grants.size() == 1,
		"Decimal flat values remain supported")
	if flat.get("grants") is Array and flat.grants.size() == 1:
		_near(float(flat.grants[0].value), 12.5, "Flat decimal value is not rounded")
	var increased: Dictionary = Parser.parse_line("2.5% increased Fire Damage")
	_expect(increased.get("supported") == true and increased.get("grants") is Array and increased.grants.size() == 1,
		"Decimal percentage values remain supported")
	if increased.get("grants") is Array and increased.grants.size() == 1:
		_near(float(increased.grants[0].value), 0.025, "Decimal percentage is converted without integer truncation")


func _expect_rejected(result: Dictionary, label: String) -> void:
	_expect(result.get("supported") == false, "Unsupported input rejects: " + label)
	_expect(result.size() == 3, "Rejected result uses the exact supported/grants/reason shape: " + label)
	_expect(result.get("grants") is Array and result.grants.is_empty(), "Unsupported input returns no grants: " + label)
	_expect(not str(result.get("reason", "")).is_empty(), "Unsupported input explains rejection: " + label)


func _near(value: float, expected: float, label: String) -> void:
	_expect(is_equal_approx(value, expected), "%s (actual %.6f, expected %.6f)" % [label, value, expected])
