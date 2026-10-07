extends SceneTree
## Focused ordinary-jewel rules, saved authority, atomicity and compatibility.
const Model = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const J = preload("res://scripts/jewel_data.gd")
const Craft = preload("res://scripts/items/jewel_craft_rules.gd")
const Planner = preload("res://scripts/items/jewel_craft_planner.gd")
const GearCraft = preload("res://scripts/items/crafting_rules.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
class FaultModel extends Model:
	var fail_save := false
	var fail_currency := false
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail_save else super._write_bytes(path, bytes)
	func _set_bag_currency_balance(candidate: Dictionary, balance: int, released: Dictionary = {}) -> Dictionary:
		var result := super._set_bag_currency_balance(candidate, balance, released)
		return {"ok": false, "error_code": "bag_full", "reason": "Injected currency placement failure"} if fail_currency else result
var checks := 0
var failures := 0
var changed_count := 0
var completed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"): quit(78); return
	for test: Callable in [_rules, _planner, _transactions, _guards, _authority, _capacity, _sockets, _legacy]:
		completed = false
		test.call()
		check(completed, "Case completed: " + test.get_method())
	print("Ordinary jewel crafting: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func source(base: String = "emberheart", rarity: String = "magic", uid: String = "jewel_000042") -> Dictionary:
	var affixes: Array = []
	for kind: String in ["prefix", "suffix"]:
		var id: String = J.BASES[base][kind + "es"][0]
		affixes.append({"id": id, "value": J.AFFIXES[id].min})
	return {"id": uid, "base": base, "rarity": rarity, "affixes": affixes}
func fixture(base: String = "emberheart", rarity: String = "magic", funds: int = 32) -> Dictionary:
	var model := FaultModel.new()
	var item := source(base, rarity, "jewel_%06d" % int(model.snapshot().next_item_serial))
	check(model._admit_reward_item(Items.wrap_jewel(item)), "Admit valid canonical jewel UID")
	var stacks: Array[String] = []
	for amount: int in [1, funds - 1] if funds > 0 else []:
		if amount <= 0: continue
		var uid := "item_%06d" % int(model.snapshot().next_item_serial)
		check(model._admit_reward_item(Items.calibration_shard(uid, amount)), "Admit actual shard stack")
		stacks.append(uid)
	var path := "user://jewel-craft-%d.json" % Time.get_ticks_usec()
	check(model.save_build(path) == OK, "Save current schema fixture")
	return {"model": model, "source": item, "stacks": stacks, "path": path}
func unchanged(f: Dictionary, before: Dictionary, disk: PackedByteArray, label: String) -> void:
	check(var_to_bytes(f.model.snapshot()) == var_to_bytes(before) and FileAccess.get_file_as_bytes(f.path) == disk, label)
func _rules() -> void:
	for base: String in J.BASES:
		for rarity: String in J.RARITIES:
			var original := source(base, rarity)
			var before := var_to_bytes(original)
			var salvage := Craft.operation_quote(original, "salvage")
			var reforge := Craft.operation_quote(original, "reforge")
			check(salvage.ok and salvage.materials == {Craft.MATERIAL_ID: 1 if rarity == "magic" else 2} and salvage.cost.is_empty() and salvage.consumes_item, "Exact fixed salvage economics " + base + rarity)
			check(reforge.ok and reforge.cost == {Craft.MATERIAL_ID: 8 if rarity == "magic" else 16} and reforge.materials.is_empty() and not reforge.consumes_item, "Exact fixed reforge economics " + base + rarity)
			check(not reforge.has("instance") and not reforge.has("seed") and not reforge.has("candidate"), "Quote reveals no random result")
			var seen := {}
			for s: int in range(32):
				var plan := Craft.operation_plan(original, "reforge", s)
				check(plan.ok and J.validate_instance(plan.instance, false), "Legal base pool, unique family and quantized bounded value")
				var result: Dictionary = plan.instance
				var prefixes := 0; var suffixes := 0
				for affix: Dictionary in result.affixes:
					if J.AFFIXES[affix.id].kind == "prefix": prefixes += 1
					else: suffixes += 1
				check(result.id == original.id and result.base == base and result.rarity == rarity, "Identity, base and rarity retained")
				check((prefixes == 1 and suffixes == 1) if rarity == "magic" else (prefixes in [1, 2] and suffixes == 2), "Exact rarity prefix/suffix counts")
				check(plan == Craft.operation_plan(original, "reforge", s), "Same input seed replays exactly")
				seen[var_to_bytes(result.affixes)] = true
			check(seen.size() > 1 and var_to_bytes(original) == before, "Real variation and input immutability")
	for operation: Variant in ["recalibrate", "targeted_reforge_damage", "augment", "enchant", "elevate", null, 1, true, &"reforge"]:
		check(not Craft.operation_quote(source(), operation).ok, "Other gear operations and malformed types rejected")
	for bad: Variant in [null, {}, source().merged({"base": "branchfinder"}, true), source().merged({"affixes": [{"id": "force", "value": 2.1}]}, true)]:
		check(not Craft.operation_quote(bad, "reforge").ok, "Malformed or illegal jewel rejected")
	for operation: String in Craft.operation_ids():
		check(Craft.operation_quote(J.generate_special("jewel_000042"), operation).code == "special_jewel", "Special branchfinder refused")
	for bad_seed: Variant in [null, true, 1.0, "1", [], {}]:
		check(not Craft.operation_plan(source(), "reforge", bad_seed).ok, "Seed is exact integer")
	seed(9101); var next := randi(); seed(9101)
	Craft.operation_plan(source(), "reforge", 9)
	check(randi() == next, "Pure reforge never advances global RNG")
	completed = true
func _planner() -> void:
	var item := source()
	var context := {"revision": 9, "jewels": {item.id: item}, "locations": {item.id: {"kind": "bag", "page": 1, "x": 11, "y": 9}}, "materials": {Craft.MATERIAL_ID: 8}, "save_writable": true}
	var before := var_to_bytes(context)
	var quote := Planner.quote(context, "reforge", item.id)
	check(quote.ok and Planner.plan(context, quote, 31).ok, "Narrow planner accepts real last bag cell")
	var result := Planner.plan(context, quote, 31)
	check(result.candidate.revision == 10 and result.candidate.materials[Craft.MATERIAL_ID] == 0 and result.candidate.locations == context.locations, "Plan increments once and retains actual cell")
	check(var_to_bytes(context) == before, "Plan never mutates context")
	for field: String in ["revision", "cost", "source_instance", "rules_version", "consumes_item"]:
		var forged := quote.duplicate(true)
		forged[field] = 0
		var rejection := Planner.plan(context, forged, 31)
		check(not rejection.ok and rejection.size() == 3, "Forged quote exposes no candidate: " + field)
	for patch: Dictionary in [{"revision": true}, {"revision": 1.0}, {"save_writable": false}, {"materials": {Craft.MATERIAL_ID: 7}}, {"materials": {Craft.MATERIAL_ID: 8.0}}, {"materials": {"other": 8}}, {"extra": 1}]:
		check(not Planner.quote(context.merged(patch, true), "reforge", item.id).ok, "Malformed or unfunded context rejected")
	for cell: Dictionary in [{"kind": "recovery", "index": 0}, {"kind": "passive_socket", "node_id": "6230"}, {"kind": "bag", "page": 0, "x": 12, "y": 0}]:
		check(not Planner.quote(context.merged({"locations": {item.id: cell}}, true), "reforge", item.id).ok, "Non-bag or invalid cell rejected")
	result.candidate.jewels[item.id].affixes.clear()
	check(var_to_bytes(context) == before and Planner.plan(context, quote, 31).ok, "Returned plan cannot alias context or future results")
	completed = true
func _transactions() -> void:
	for base: String in J.BASES:
		for rarity: String in J.RARITIES:
			var cost := 8 if rarity == "magic" else 16
			var f := fixture(base, rarity, cost)
			var model: FaultModel = f.model
			var before := model.snapshot(); var disk := FileAccess.get_file_as_bytes(f.path)
			var location := model.location(f.source.id)
			var seq := model._craft_sequence
			var metadata := model.crafting_operations(f.source.id, f.path)
			check(metadata.size() == 2 and metadata[0].operation == "salvage" and metadata[1].operation == "reforge" and metadata[1].cost[Craft.MATERIAL_ID] == cost, "Only correct jewel metadata")
			check(model._craft_sequence == seq and model._craft_quotes.is_empty(), "Metadata issues no handle")
			var quote := model.crafting_quote("reforge", f.source.id, f.path)
			check(quote.ok, "Authoritative jewel quote issued")
			if not quote.ok: return
			quote.cost[Craft.MATERIAL_ID] = 0
			quote.source_instance.affixes.clear()
			var seed_text := JSON.stringify({"rules": Craft.RULES_VERSION + ":reforge", "revision": before.crafting.revision, "item": f.source}, "", true, true)
			var expected := Craft.operation_plan(f.source, "reforge", seed_text.sha256_text().substr(0, 15).hex_to_int())
			changed_count = 0; model.changed.connect(func(): changed_count += 1)
			var saves := model.successful_saves
			model.fail_currency = true
			check(not model.execute_crafting(quote.handle, f.source).ok, "Currency placement failure rejects candidate")
			unchanged(f, before, disk, "Currency candidate failure preserves full memory and disk")
			model.fail_currency = false; model.fail_save = true
			check(not model.execute_crafting(quote.handle, f.source).ok, "Atomic save failure surfaced")
			unchanged(f, before, disk, "Failed write preserves currency, identity, positions and revisions")
			check(model.successful_saves == saves and changed_count == 0, "Failures emit no changed or successful save")
			model.fail_save = false
			var result := model.execute_crafting(quote.handle, f.source)
			check(result.ok and model.item(f.source.id).payload == expected.instance and model.location(f.source.id) == location, "Retry applies authoritative deterministic result at same location")
			check(model.crafting_balance() == 0 and model.item(f.stacks[0]).is_empty() and model.item(f.stacks[1]).is_empty(), "Exact debit consumes actual split stacks")
			var after := model.snapshot()
			check(after.version == before.version and after.next_item_serial == before.next_item_serial and after.crafting.revision == before.crafting.revision + 1 and after.revision == before.revision + 1, "No schema or serial bump; both revisions once")
			check(changed_count == 1 and model.successful_saves == saves + 1, "One changed signal and one save")
			for uid: String in before.items:
				if uid == f.source.id or f.stacks.has(uid): continue
				check(after.items[uid] == before.items[uid] and after.locations[uid] == before.locations[uid], "Unrelated item/payload/location preserved")
			check(not model.execute_crafting(quote.handle, f.source).ok and model.snapshot() == after, "Double confirm cannot charge twice")
			var loaded := Model.new()
			check(loaded.load_build(f.path) and loaded.snapshot() == after, "Full current-schema save roundtrip")
			var rolled: Dictionary = model.item(f.source.id).payload
			quote = model.crafting_quote("salvage", f.source.id, f.path)
			check(quote.ok and model.execute_crafting(quote.handle, rolled).ok, "Rolled jewel can be salvaged")
			check(model.item(f.source.id).is_empty() and model.crafting_balance() == (1 if rarity == "magic" else 2), "Salvage removes one exact UID with fixed credit")
	completed = true
func _guards() -> void:
	var f := fixture("emberheart", "magic", 7)
	var model: FaultModel = f.model
	var before := model.snapshot(); var disk := FileAccess.get_file_as_bytes(f.path)
	check(not model.crafting_quote("reforge", f.source.id, f.path).ok and not model.crafting_operations(f.source.id, f.path)[1].available, "Insufficient bag funds prevent quote and disable metadata")
	check(not model.crafting_quote("salvage", f.source.id, f.path + ".other").ok, "Cannot quote into another profile")
	check(model.town_claim_offer("currency", model.revision(), f.path).error_code == "test_profile_required", "Free test source remains isolated")
	unchanged(f, before, disk, "Guard failures preserve all state")
	var candidate := model.snapshot(); candidate.locations[f.source.id] = {"kind": "recovery", "index": 0}
	check(Rules.reason(candidate).is_empty(), "Recovery fixture is a legal build")
	model._accept_memory(candidate); check(model.save_build(f.path) == OK, "Persist legal recovery fixture")
	check(not model.crafting_quote("salvage", f.source.id, f.path).ok and not model.crafting_operations(f.source.id, f.path)[0].available, "Recovery jewel cannot be crafted")
	f = fixture(); model = f.model
	var special := model.award_special_jewel(); check(model.save_build(f.path) == OK, "Persist special jewel")
	before = model.snapshot(); disk = FileAccess.get_file_as_bytes(f.path)
	for op: String in Craft.operation_ids():
		check(model.crafting_quote(op, special, f.path).code == "special_jewel", "Bag special jewel rejected")
		check(not model.crafting_operations(special, f.path)[0].available, "Special metadata is disabled")
	unchanged(f, before, disk, "Special rejection preserves intrinsic rules and all inventory")
	completed = true
func _authority() -> void:
	var f := fixture(); var model: FaultModel = f.model
	var before := model.snapshot(); var disk := FileAccess.get_file_as_bytes(f.path)
	var q := model.crafting_quote("reforge", f.source.id, f.path)
	check(q.ok, "Authority fixture quote")
	model.cancel_crafting_quote(q.handle)
	check(not model.execute_crafting(q.handle, f.source).ok, "Canceled quote rejected")
	q = model.crafting_quote("reforge", f.source.id, f.path)
	var wrong: Dictionary = f.source.duplicate(true); wrong.id = "jewel_000999"
	check(model.execute_crafting(q.handle, wrong).code == "source_mismatch", "Changed selection rejected")
	model._craft_quotes[q.handle].expires_msec = Time.get_ticks_msec()
	check(model.execute_crafting(q.handle, f.source).code == "expired_quote", "Exact expiry boundary rejects and removes authority")
	q = model.crafting_quote("reforge", f.source.id, f.path)
	for i: int in range(8): model.crafting_quote("reforge", f.source.id, f.path)
	check(model._craft_quotes.size() == 8 and not model.execute_crafting(q.handle, f.source).ok, "Bounded quote eviction")
	unchanged(f, before, disk, "Canceled, changed-source, expired and evicted quotes change nothing")
	q = model.crafting_quote("reforge", f.source.id, f.path)
	check(model.load_build(f.path) and not model.execute_crafting(q.handle, f.source).ok, "Loading even same file clears authority")
	q = model.crafting_quote("reforge", f.source.id, f.path)
	model.add_xp(1); before = model.snapshot()
	check(not model.execute_crafting(q.handle, f.source).ok and model.snapshot() == before, "Intervening global revision invalidates quote")
	check(model.save_build(f.path) == OK, "Persist legitimate intermediate state")
	q = model.crafting_quote("reforge", f.source.id, f.path)
	check(model.save_build(f.path + ".switched") == OK, "Switch open file without changing build")
	check(model.execute_crafting(q.handle, f.source).code == "profile_changed", "Same build on another open file cannot spend old quote")
	f = fixture(); model = f.model; q = model.crafting_quote("reforge", f.source.id, f.path)
	var file := FileAccess.open(f.path, FileAccess.WRITE); file.store_string(JSON.stringify(model.snapshot(), "  ")); file.close()
	before = model.snapshot(); disk = FileAccess.get_file_as_bytes(f.path)
	check(model.execute_crafting(q.handle, f.source).code == "save_changed", "Same semantic save with changed bytes rejects")
	unchanged(f, before, disk, "External disk bytes are never overwritten")
	f = fixture(); model = f.model; q = model.crafting_quote("reforge", f.source.id, f.path)
	model.retire_profile()
	check(not model.execute_crafting(q.handle, f.source).ok, "Retired profile cannot execute")
	completed = true
func _capacity() -> void:
	var f := fixture("windweave", "rare", 0); var model: FaultModel = f.model
	var candidate := model.snapshot()
	var occupied := {}
	for uid: String in candidate.items:
		var cell: Dictionary = candidate.locations[uid]
		if cell.kind != "bag": continue
		var dimensions: Array = Items.metadata_for_items({uid: candidate.items[uid]})[uid].size
		for y: int in range(cell.y, cell.y + int(dimensions[1])):
			for x: int in range(cell.x, cell.x + int(dimensions[0])): occupied[Vector3i(cell.page, x, y)] = true
	for page: int in range(2):
		for y: int in range(10):
			for x: int in range(12):
				if occupied.has(Vector3i(page, x, y)): continue
				var uid := "jewel_%06d" % int(candidate.next_item_serial)
				candidate.items[uid] = Items.wrap_jewel(source("emberheart", "magic", uid))
				candidate.locations[uid] = {"kind": "bag", "page": page, "x": x, "y": y}
				candidate.next_item_serial += 1
	check(Rules.reason(candidate).is_empty(), "Both full bag pages are legal")
	model._accept_memory(candidate); check(model.save_build(f.path) == OK, "Persist full bags without any currency stack")
	var cell := model.location(f.source.id)
	var old_items: Dictionary = model.snapshot().items
	var q := model.crafting_quote("salvage", f.source.id, f.path)
	check(q.ok and model.execute_crafting(q.handle, f.source).ok, "Full bag salvage places earned stack in freed jewel cell")
	for uid: String in model.snapshot().items:
		if not old_items.has(uid): check(model.location(uid) == cell and model.item(uid).payload.quantity == 2, "New currency preserves page and cell")
	f = fixture("emberheart", "magic", 0); model = f.model
	candidate = model.snapshot(); candidate.next_item_serial = Rules.MAX_SERIAL
	check(Rules.reason(candidate).is_empty(), "Exhausted serial fixture legal")
	model._accept_memory(candidate); check(model.save_build(f.path) == OK, "Persist serial boundary")
	var before := model.snapshot(); var disk := FileAccess.get_file_as_bytes(f.path)
	check(not model.crafting_quote("salvage", f.source.id, f.path).ok, "Cannot delete jewel when new currency cannot get an identity")
	unchanged(f, before, disk, "Currency stack creation failure preserves jewel and revisions")
	f = fixture("emberheart", "magic", 1); model = f.model
	candidate = model.snapshot(); candidate.items[f.stacks[0]].payload.quantity = 1000000000
	model._accept_memory(candidate); check(model.save_build(f.path) == OK, "Persist currency total boundary")
	before = model.snapshot(); disk = FileAccess.get_file_as_bytes(f.path)
	check(not model.crafting_quote("salvage", f.source.id, f.path).ok, "Inventory shard limit rejects salvage")
	unchanged(f, before, disk, "Currency overflow rejection changes nothing")
	completed = true
func _sockets() -> void:
	var f := fixture(); var model: FaultModel = f.model
	for id: String in ["2151", "37690", "48423", "6230"]:
		check(model.allocate_passive(id, 0, model.revision(), f.path).ok, "Allocate real source socket path")
	check(model.move_item(f.source.id, {"kind": "passive_socket", "node_id": "6230"}, model.revision(), f.path).ok, "Socket ordinary jewel")
	var before := model.snapshot(); var disk := FileAccess.get_file_as_bytes(f.path)
	check(not model.crafting_quote("reforge", f.source.id, f.path).ok and not model.crafting_quote("salvage", f.source.id, f.path).ok, "Socketed ordinary jewel refuses both crafts")
	unchanged(f, before, disk, "Socket position and stats remain intact")
	check(model.move_item(f.source.id, model.first_bag_position(f.source.id), model.revision(), f.path).ok, "Return ordinary jewel to bag")
	var special := model.award_special_jewel()
	check(model.move_item(special, {"kind": "passive_socket", "node_id": "6230"}, model.revision(), f.path).ok, "Socket special rule source")
	check(model.allocate_passive("26740", 0, model.revision(), f.path).ok, "Allocate actual radius-supported remote node")
	var analysis := model.passive_analysis(); var stats := model.get_stats()
	var talents: Dictionary = model.snapshot().talents
	var q := model.crafting_quote("reforge", f.source.id, f.path)
	check(q.ok and model.execute_crafting(q.handle, f.source).ok, "Ordinary bag reforge with active special support")
	check(model.passive_analysis() == analysis and model.get_stats() == stats and model.snapshot().talents == talents and model.location(special) == {"kind": "passive_socket", "node_id": "6230"}, "Special support, real stats, talents and socket remain exact")
	check(not model.move_item(special, model.first_bag_position(special), model.revision(), f.path).ok, "Existing special support removal guard remains active")
	completed = true
func _legacy() -> void:
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/special_jewel_legacy_rng.json"))
	check(J.BASES == str_to_var(frozen.bases) and J.RARITIES == str_to_var(frozen.rarities) and J.AFFIXES == str_to_var(frozen.affixes), "All ordinary definitions equal frozen baseline")
	for sequence: Dictionary in frozen.sequences:
		var rng := RandomNumberGenerator.new(); rng.seed = int(sequence.seed)
		for sample: Dictionary in sequence.samples:
			Craft.operation_plan(source(), "reforge", 42)
			var item := J.generate(rng, sample.instance.id)
			check(item == sample.instance and str(rng.state) == sample.rng_state, "Natural jewel output and RNG state unchanged around crafting")
	var model := FaultModel.new()
	var id := "gear_%06d" % int(model.snapshot().next_item_serial)
	var gear := {"id": id, "base_id": "ashwood_bow", "rarity": "magic", "item_level": 30, "affixes": [{"id": "whetstone_edge", "tier": 1, "value": 1}]}
	check(model._admit_reward_item(Items.wrap_equipment(gear)), "Existing gear admitted")
	var uid := "item_%06d" % int(model.snapshot().next_item_serial)
	check(model._admit_reward_item(Items.calibration_shard(uid, 1000)), "Existing gear funded")
	var path := "user://jewel-legacy-gear.json"; check(model.save_build(path) == OK, "Save legacy gear control")
	check(model.crafting_operations(id, path).size() == 10, "Six released and four targeted gear operations remain")
	for op: String in ["recalibrate", "reforge", "targeted_reforge_damage"]:
		var src: Dictionary = model.item(id).payload
		var q := model.crafting_quote(op, id, path)
		var seed_text := JSON.stringify({"rules": GearCraft.seed_rules_version(op), "revision": int(model.snapshot().crafting.revision), "item": src}, "", true, true)
		var expected := GearCraft.operation_plan(src, op, seed_text.sha256_text().substr(0, 15).hex_to_int())
		check(q.ok and model.execute_crafting(q.handle, src).ok and model.item(id).payload == expected.instance, "Existing equipment rules and seed routing remain exact: " + op)
	completed = true
