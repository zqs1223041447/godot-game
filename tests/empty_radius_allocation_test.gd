extends SceneTree
## Exact v050/v051 comparison on the production pinned allocation context.
## Only the optional private-path timing excludes public context validation.
const Current = preload("res://scripts/passives/source_tree_allocation_rules.gd")
const Before = preload("res://tests/fixtures/v051/source_tree_allocation_before.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const ORIGINAL_SHA256 := "a49093d9d8eb02ce80cb5070f4cdca98081e7a985abe89f61d54ae4bb6d76750"
const FROZEN_SHA256 := "fadba5f6cf2104e7fef26ddd21a83db230abbad19310778529844b9d8969da8e"
const GLOBAL_RNG_SEED := 510051
const SOCKET_ID := "6230"
const REMOTE_ID := "26740"
const SOCKET_PATH := ["58833", "2151", "37690", "48423", "6230"]
const TIMING_REPEATS := 5
const TIMING_CALLS := 8
var checks := 0
var failures := 0
var cases: Array[Dictionary] = []
var timings: Array[Dictionary] = []
var local_rng := RandomNumberGenerator.new()
var local_rng_state := 0
var expected_global_next := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)


func run() -> void:
	for variable: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		if not OS.get_environment(variable).begins_with("/tmp/godot-m1-v051-allocation-"):
			push_error("Use fresh isolated /tmp/godot-m1-v051-allocation-* XDG roots")
			quit(78); return
	var output := OS.get_environment("ALLOCATION_V051_OUT")
	var allowed_output := ProjectSettings.globalize_path("res://docs/qa/v051-allocation/")
	if output.is_empty() or not output.begins_with(allowed_output) or output.contains(".."):
		push_error("ALLOCATION_V051_OUT must be inside docs/qa/v051-allocation/")
		quit(78); return
	var frozen := FileAccess.get_file_as_string("res://tests/fixtures/v051/source_tree_allocation_before.gd")
	check(frozen.sha256_text() == FROZEN_SHA256, "Frozen fixture bytes match recorded SHA-256")
	check(frozen.replace("class_name FrozenV051Allocation\n", "class_name SourceTreeAllocationRules\n").sha256_text() == ORIGINAL_SHA256,
		"Reversing only the class name restores exact v050 production bytes")
	# The production owner prepares and validates this private pinned graph once.
	# Detach the fixture so invalid/reordered cases cannot modify its retained graph.
	var context: Dictionary = Runtime._context(0, 123).duplicate(true)
	check(not context.is_empty() and context.nodes.size() == 2387 and context.start_id == "58833",
		"Use the actual 2,387-node pinned Scion allocation context")
	if context.is_empty(): quit(1); return
	check(Current._context_error(context).is_empty() and Before._context_error(context).is_empty(),
		"Both public context validators accept the unchanged production graph")
	local_rng.seed = GLOBAL_RNG_SEED
	local_rng_state = local_rng.state
	seed(GLOBAL_RNG_SEED); expected_global_next = randi()
	var context_bytes := var_to_bytes(context)
	var start := {"allocated": [context.start_id], "masteries": {}}
	var connected := {"allocated": SOCKET_PATH.duplicate(), "masteries": {}}
	var remote: Dictionary = connected.duplicate(true)
	remote.allocated.append(REMOTE_ID)
	var ordinary := {SOCKET_ID: {"rule_id": "", "radius": 0.0}}
	var special := {SOCKET_ID: {"rule_id": "disconnected_radius", "radius": 280.0}}
	var no_jewel := pair("no_jewel_start", context, start, {}, true)
	check(no_jewel.remote_sources.is_empty() and no_jewel.active_sockets.is_empty(), "No jewel grants no remote coverage")
	pair("no_jewel_connected_path", context, connected, {}, true)
	var ordinary_result := pair("ordinary_jewel", context, connected, ordinary, true)
	check(ordinary_result.active_sockets == [SOCKET_ID] and ordinary_result.remote_sources.is_empty(),
		"Ordinary jewel remains active without granting remote coverage")
	pair("illegal_disconnected_without_jewel", context, remote, {}, false)
	pair("illegal_disconnected_ordinary_jewel", context, remote, ordinary, false)
	var special_result := pair("actual_280_radius_jewel", context, remote, special, true)
	check(special_result.remote_sources.get(REMOTE_ID, []) == [SOCKET_ID] and not special_result.normal_connected.has(REMOTE_ID),
		"Real radius jewel authorizes the real remote node without changing normal connectivity")
	# The true node distance can round on sqrt/square; compare its exact squared
	# boundary explicitly, plus an unambiguous sample just inside and just outside.
	var distance_squared: float = context.nodes[SOCKET_ID].position.distance_squared_to(context.nodes[REMOTE_ID].position)
	var radius := sqrt(distance_squared)
	for offset: float in [-0.000001, 0.0, 0.000001]:
		var boundary_radius := radius + offset
		var boundary := {SOCKET_ID: {"rule_id": "disconnected_radius", "radius": boundary_radius}}
		pair("real_radius_boundary_%s" % str(offset), context, remote, boundary, distance_squared <= boundary_radius * boundary_radius)
	pair("zero_radius_rejects_remote", context, remote, {SOCKET_ID: {"rule_id": "disconnected_radius", "radius": 0.0}}, false)
	pair("unallocated_socket", context, start, ordinary, false)
	pair("disconnected_socket", context, {"allocated": [context.start_id, SOCKET_ID], "masteries": {}}, special, false)
	var missing_bridge: Dictionary = remote.duplicate(true)
	missing_bridge.allocated.erase("48423")
	pair("missing_socket_path_bridge", context, missing_bridge, special, false)
	var exact_budget: Dictionary = context.duplicate(false)
	exact_budget.budget = remote.allocated.size() - 1
	pair("exact_point_budget", exact_budget, remote, special, true)
	var insufficient_budget: Dictionary = context.duplicate(false)
	insufficient_budget.budget = remote.allocated.size() - 2
	pair("insufficient_point_budget", insufficient_budget, remote, special, false)
	for entry: Dictionary in [
		{"label": "unknown_rule", "rule": {"rule_id": "future_rule", "radius": 280.0}},
		{"label": "integer_radius", "rule": {"rule_id": "disconnected_radius", "radius": 280}},
		{"label": "negative_radius", "rule": {"rule_id": "disconnected_radius", "radius": -1.0}},
		{"label": "infinite_radius", "rule": {"rule_id": "disconnected_radius", "radius": INF}},
		{"label": "ordinary_nonzero_radius", "rule": {"rule_id": "", "radius": 1.0}},
	]:
		pair(entry.label, context, connected, {SOCKET_ID: entry.rule}, false)
	var duplicate: Dictionary = connected.duplicate(true)
	duplicate.allocated.append(SOCKET_ID)
	pair("duplicate_allocation", context, duplicate, {}, false)
	pair("unknown_allocation", context, {"allocated": [context.start_id, "missing_node"], "masteries": {}}, {}, false)
	pair("unknown_mastery_selection", context, {"allocated": [context.start_id], "masteries": {SOCKET_ID: 1}}, {}, false)
	var reversed_context := reverse_keys(context)
	reversed_context.nodes = reverse_keys(context.nodes)
	reversed_context.adjacency = reverse_keys(context.adjacency)
	var reversed_selection := reverse_keys(remote)
	reversed_selection.allocated = remote.allocated.duplicate()
	reversed_selection.allocated.reverse()
	var reversed_special := {SOCKET_ID: reverse_keys(special[SOCKET_ID])}
	var reordered := pair("reordered_real_graph_selection_and_socket", reversed_context, reversed_selection, reversed_special, true)
	check(var_to_bytes(reordered) == var_to_bytes(special_result), "Reordered successful input produces identical typed result bytes")
	var reordered_empty := pair("reordered_no_jewel", reversed_context, reverse_keys(start), {}, true)
	check(var_to_bytes(reordered_empty) == var_to_bytes(no_jewel), "Reordered empty-radius path has identical typed results")
	var reversed_connected := reverse_keys(connected)
	reversed_connected.allocated = connected.allocated.duplicate()
	reversed_connected.allocated.reverse()
	var reordered_ordinary := pair("reordered_ordinary_jewel", reversed_context, reversed_connected,
		{SOCKET_ID: reverse_keys(ordinary[SOCKET_ID])}, true)
	check(var_to_bytes(reordered_ordinary) == var_to_bytes(ordinary_result), "Reordered ordinary-jewel path has identical typed results")
	# Invalid public contexts must still fail full validation before the new guard.
	var invalid_context: Dictionary = context.duplicate(true)
	invalid_context.nodes[context.start_id].type = "unknown_type"
	pair("invalid_public_node_context", invalid_context, start, {}, false, false)
	var float_budget: Dictionary = context.duplicate(false)
	float_budget.budget = 123.0
	pair("invalid_public_budget_type", float_budget, start, {}, false, false)
	# Returned authorization arrays and nested source lists remain detached.
	var detached: Dictionary = special_result.duplicate(true)
	special_result.normal_connected.clear()
	special_result.active_sockets.clear()
	special_result.remote_sources[REMOTE_ID].clear()
	special_result.remote_sources.clear()
	var after_mutation := observed(false, true, context, remote, special, "detached_result_recheck")
	check(var_to_bytes(after_mutation) == var_to_bytes(detached), "Mutating prior output does not affect later authorization")
	check(var_to_bytes(context) == context_bytes, "All cases leave the original pinned fixture byte-identical")
	if OS.get_environment("ALLOCATION_V051_TIMING") == "1" and failures == 0:
		for spec: Dictionary in [
			{"label": "no_jewel", "selection": start, "socketed": {}},
			{"label": "ordinary_jewel", "selection": connected, "socketed": ordinary},
			{"label": "actual_280_radius_jewel", "selection": remote, "socketed": special},
		]:
			measure(spec, context)
	var report := {"baseline_revision": "7b1642d", "baseline_source_sha256": ORIGINAL_SHA256,
		"frozen_fixture_sha256": FROZEN_SHA256, "production_source_sha256": FileAccess.get_file_as_string("res://scripts/passives/source_tree_allocation_rules.gd").sha256_text(),
		"engine": Engine.get_version_info().string, "display_server": DisplayServer.get_name(),
		"context_nodes": context.nodes.size(), "context_typed_bytes_hex_sha256": context_bytes.hex_encode().sha256_text(),
		"real_socket_id": SOCKET_ID, "real_remote_node_id": REMOTE_ID, "checks": checks, "failures": failures,
		"cases": cases, "timings": timings,
		"scope": "Pure allocation-rule comparison on the real pinned graph. Both public full-input validation and the production validated-context path are checked. Timing covers only the private analysis body; fixture construction, public graph validation, serialization and checks are outside the timed spans. No gameplay, save, reward-settlement, rendered-frame or Windows-FPS performance claim."}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write allocation comparison report"); quit(1); return
	file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("EMPTY_RADIUS_ALLOCATION_COMPLETE %d checks, %d failures, %d cases: %s" % [checks, failures, cases.size(), output])
	quit(1 if failures else 0)


func pair(label: String, context: Dictionary, selection: Dictionary, socketed: Dictionary,
		expected_legal: bool, validated_context: bool = true) -> Dictionary:
	var inputs := var_to_bytes([context, selection, socketed])
	var baseline := observed(true, false, context, selection, socketed, label + ": baseline public")
	var current := observed(false, false, context, selection, socketed, label + ": current public")
	check(var_to_bytes(baseline) == var_to_bytes(current), label + ": exact public result bytes including types/order/error")
	check(current.legal == expected_legal, label + ": expected legal/rejected outcome")
	if validated_context:
		var baseline_private := observed(true, true, context, selection, socketed, label + ": baseline private")
		var current_private := observed(false, true, context, selection, socketed, label + ": current private")
		check(var_to_bytes(baseline_private) == var_to_bytes(baseline), label + ": public/private baseline agree")
		check(var_to_bytes(current_private) == var_to_bytes(current), label + ": public/private current agree")
	if not current.legal:
		check(current.normal_connected.is_empty() and current.remote_sources.is_empty() and current.active_sockets.is_empty(),
			label + ": rejection exposes no partial authorization")
	check(var_to_bytes([context, selection, socketed]) == inputs, label + ": full typed input bytes unchanged")
	cases.append({"case": label, "legal": current.legal, "reason": current.reason,
		"input_typed_bytes_hex_sha256": inputs.hex_encode().sha256_text(),
		"result_typed_bytes_hex": var_to_bytes(current).hex_encode(), "private_path_checked": validated_context})
	return current


func observed(before: bool, fast: bool, context: Dictionary, selection: Dictionary, socketed: Dictionary, label: String) -> Dictionary:
	var inputs := var_to_bytes([context, selection, socketed])
	seed(GLOBAL_RNG_SEED)
	var value: Dictionary
	if before:
		value = Before._analyze_validated_context(context, selection, socketed) if fast else Before.analyze(context, selection, socketed)
	else:
		value = Current._analyze_validated_context(context, selection, socketed) if fast else Current.analyze(context, selection, socketed)
	check(randi() == expected_global_next and local_rng.state == local_rng_state, label + ": global stream/local RNG unchanged")
	check(var_to_bytes([context, selection, socketed]) == inputs, label + ": input immutability")
	return value


func reverse_keys(value: Dictionary) -> Dictionary:
	var result := {}
	var keys := value.keys()
	keys.reverse()
	for key: Variant in keys:
		result[key] = value[key]
	return result


func measure(spec: Dictionary, context: Dictionary) -> void:
	var expected := var_to_bytes(Before._analyze_validated_context(context, spec.selection, spec.socketed))
	var before_samples: Array[int] = []
	var current_samples: Array[int] = []
	var inputs := var_to_bytes([context, spec.selection, spec.socketed])
	# Warm both code paths, then alternate execution order to reduce order bias.
	Current._analyze_validated_context(context, spec.selection, spec.socketed)
	for repetition: int in range(TIMING_REPEATS):
		for use_before: bool in ([true, false] if repetition % 2 == 0 else [false, true]):
			seed(GLOBAL_RNG_SEED)
			var result: Dictionary
			var began := Time.get_ticks_usec()
			for unused: int in range(TIMING_CALLS):
				result = Before._analyze_validated_context(context, spec.selection, spec.socketed) if use_before \
					else Current._analyze_validated_context(context, spec.selection, spec.socketed)
			var elapsed := Time.get_ticks_usec() - began
			if use_before: before_samples.append(elapsed)
			else: current_samples.append(elapsed)
			check(var_to_bytes(result) == expected, spec.label + ": timing batch preserves exact result")
			check(randi() == expected_global_next and local_rng.state == local_rng_state, spec.label + ": timing batch preserves RNG")
	check(var_to_bytes([context, spec.selection, spec.socketed]) == inputs, spec.label + ": timing leaves input unchanged")
	timings.append({"case": spec.label, "calls_per_batch": TIMING_CALLS, "samples": TIMING_REPEATS,
		"before_batch_us": before_samples, "current_batch_us": current_samples,
		"before_median_per_call_us": median_per_call(before_samples), "current_median_per_call_us": median_per_call(current_samples)})


func median_per_call(samples: Array[int]) -> float:
	var ordered := samples.duplicate()
	ordered.sort()
	return float(ordered[int(ordered.size() / 2)]) / TIMING_CALLS
