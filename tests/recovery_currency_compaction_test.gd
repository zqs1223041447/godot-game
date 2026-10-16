extends "res://tests/jewel_crafting_test.gd"
## Item-count reductions must retain the recovery queue's identities and order.
const Maps = preload("res://scripts/world/map_compiler.gd")

func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-m1-"):
		quit(78)
		return
	for scenario: String in ["salvage", "reforge_one", "reforge_split", "gear"]:
		craft_case(scenario)
	gem_case()
	map_guard_case()
	print("Recovery currency compaction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func add_recovery(f: Dictionary) -> void:
	var model: FaultModel = f.model
	var ids: Array[String] = []
	for i: int in range(3):
		var uid := "jewel_%06d" % int(model.snapshot().next_item_serial)
		check(model._admit_reward_item(Items.wrap_jewel(source("emberheart", "magic", uid))), "Admit unrelated recovery item")
		ids.append(uid)
	# Deliberately reverse UID/insertion order and leave valid sparse indices.
	ids.reverse()
	var candidate := model.snapshot()
	for i: int in range(ids.size()):
		candidate.locations[ids[i]] = {"kind": "recovery", "index": candidate.items.size() - ids.size() + i}
	candidate.revision += 1
	check(Rules.reason(candidate).is_empty(), "Sparse high-index recovery is canonical")
	model._accept_memory(candidate)
	check(model.save_build(f.path) == OK, "Persist real recovery fixture")
	check(model.pending_items() == ids, "Recovery order differs from UID order")
	f.recovery = ids

func assert_recovery(f: Dictionary, before: Dictionary) -> void:
	var model: FaultModel = f.model
	check(model.pending_items() == f.recovery, "Recovery UID and relative order retained")
	for i: int in range(f.recovery.size()):
		var uid: String = f.recovery[i]
		check(model.item(uid) == before.items[uid] and model.location(uid) == {"kind": "recovery", "index": i}, "Recovery payload retained and index compacted")
	check(Rules.reason(model.snapshot()).is_empty(), "Final complete candidate canonical")
	var loaded := Model.new()
	check(loaded.load_build(f.path) and loaded.snapshot() == model.snapshot(), "Persisted compacted state roundtrips")

func craft_case(scenario: String) -> void:
	var f := fixture("emberheart", "magic", 8)
	var model: FaultModel = f.model
	var op := "salvage" if scenario == "salvage" else "reforge"
	if scenario == "reforge_one":
		var candidate := model.snapshot()
		candidate.items[f.stacks[1]].payload.quantity = 8
		candidate.items.erase(f.stacks[0]); candidate.locations.erase(f.stacks[0])
		model._accept_memory(candidate)
		f.stacks = [f.stacks[1]]
	if scenario == "gear":
		var uid := "gear_%06d" % int(model.snapshot().next_item_serial)
		var gear := {"id": uid, "base_id": "ashwood_bow", "rarity": "magic", "item_level": 30, "affixes": [{"id": "whetstone_edge", "tier": 1, "value": 1}]}
		check(model._admit_reward_item(Items.wrap_equipment(gear)), "Admit actual equipment")
		f.source = gear
		op = "recalibrate"
		var cost: int = GearCraft.operation_quote(gear, op).cost[Craft.MATERIAL_ID]
		var candidate := model.snapshot()
		candidate.items[f.stacks[1]].payload.quantity = cost - 1
		model._accept_memory(candidate)
	add_recovery(f)
	var before := model.snapshot()
	var disk := FileAccess.get_file_as_bytes(f.path)
	var saves := model.successful_saves
	changed_count = 0
	model.changed.connect(func(): changed_count += 1)
	var q := model.crafting_quote(op, f.source.id, f.path)
	check(q.ok, scenario + ": legal quote")
	unchanged(f, before, disk, "Quote does not compact live state or write disk")
	check(model.successful_saves == saves and changed_count == 0, "Quote saves nothing")
	if not q.ok: return
	model.fail_save = true
	var rejected := model.execute_crafting(q.handle, f.source)
	check(not rejected.ok and rejected.code == "save_failed", scenario + ": reaches injected write failure")
	unchanged(f, before, disk, "Failed write rolls back queue, items, currency and revisions")
	check(model.successful_saves == saves and changed_count == 0, "Failed write has no successful save or signal")
	model.fail_save = false
	var result := model.execute_crafting(q.handle, f.source)
	check(result.ok, scenario + ": same quote retry succeeds")
	if not result.ok: return
	assert_recovery(f, before)
	check(model.crafting_balance() == (9 if op == "salvage" else 0), "Exact currency credit/debit, no duplication")
	check(model.snapshot().items.size() == before.items.size() - (1 if op == "salvage" else f.stacks.size()), "Only consumed item/empty stacks removed")
	if op == "salvage": check(model.item(f.source.id).is_empty(), "Exact salvaged UID removed")
	else: check(model.item(f.source.id).payload.id == f.source.id and model.location(f.source.id) == before.locations[f.source.id], "Crafted identity and bag position retained")
	var after := model.snapshot()
	for uid: String in before.items:
		if uid == f.source.id or f.stacks.has(uid) or f.recovery.has(uid): continue
		check(after.items[uid] == before.items[uid] and after.locations[uid] == before.locations[uid], "Unrelated non-recovery item and position unchanged")
	check(after.revision == before.revision + 1 and after.crafting.revision == before.crafting.revision + 1 and after.next_item_serial == before.next_item_serial and after.version == before.version, "Single revisions, stable schema and serial")
	check(model.successful_saves == saves + 1 and changed_count == 1, "Exactly one successful save and signal")
	check(not model.execute_crafting(q.handle, f.source).ok and model.snapshot() == after and model.successful_saves == saves + 1, "Repeated confirmation cannot duplicate currency or save")

func gem_case() -> void:
	var f := fixture("emberheart", "magic", 8)
	var model: FaultModel = f.model
	var uid := "item_%06d" % int(model.snapshot().next_item_serial)
	check(model._admit_reward_item(Model.Gems.create_instance(uid, "support:efficiency")), "Admit recyclable gem")
	f.path = "user://build_save.json"
	add_recovery(f)
	var before := model.snapshot()
	var disk := FileAccess.get_file_as_bytes(f.path)
	var saves := model.successful_saves
	var q := model.gem_trade_quote("recycle", uid, model.revision(), f.path)
	check(q.ok, "Gem recycle quote accepts high recovery indices")
	unchanged(f, before, disk, "Gem quote leaves live queue untouched")
	if not q.ok: return
	model.fail_save = true
	check(model.execute_gem_trade(q.handle, uid).code == "save_failed", "Gem recycle reaches injected write failure")
	unchanged(f, before, disk, "Gem recycle rollback exact")
	model.fail_save = false
	check(not model.execute_gem_trade(q.handle, uid).ok, "Failed gem quote remains single-use")
	q = model.gem_trade_quote("recycle", uid, model.revision(), f.path)
	check(q.ok and model.execute_gem_trade(q.handle, uid).ok, "Gem recycle fresh quote retries")
	assert_recovery(f, before)
	check(model.item(uid).is_empty() and model.crafting_balance() == 8 + Model.GemTrade.RECYCLE_CREDIT and model.successful_saves == saves + 1, "Gem recycle credits once and saves once")
	var after := model.snapshot()
	check(not model.execute_gem_trade(q.handle, uid).ok and model.snapshot() == after and model.successful_saves == saves + 1, "Gem repeated confirmation inert")

func map_guard_case() -> void:
	# The preceding normal-profile case owns this isolated temporary file.
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path("user://build_save.json")) == OK, "Reset isolated normal profile")
	var f := fixture("emberheart", "magic", 8)
	f.path = "user://build_save.json"
	add_recovery(f)
	var model: FaultModel = f.model
	var before := model.snapshot()
	var disk := FileAccess.get_file_as_bytes(f.path)
	var profile: Dictionary = Maps.compile_normal("old_garden", 2, [], []).profile
	var result := model.normal_start_map(profile, model.revision(), f.path)
	check(not result.ok and result.error_code == "pending_items", "Paid map entry still blocks unresolved recovery before debit")
	unchanged(f, before, disk, "Blocked map entry leaves currency, queue and disk exact")
