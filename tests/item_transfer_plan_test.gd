extends SceneTree
const Planner = preload("res://scripts/items/item_transfer_plan.gd")
const Layout = preload("res://scripts/items/item_location_rules.gd")
const Slots = preload("res://scripts/items/equipment_slots.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
func context(recovery: bool = false) -> Dictionary:
	var equip: Dictionary = {}
	for slot: String in Slots.all_slots(): equip[slot] = Slots.category_for_slot(slot)
	return {"columns":12,"rows":8,"equipment_slots":equip,"skill_group_ids":["group_1","group_2"],"passive_socket_ids":["58833"],"allow_recovery":recovery}
func meta(kind: String, category: String = "", size: Array = [1,1]) -> Dictionary:
	return {"kind":kind,"category":category,"size":size.duplicate()}
func run() -> void:
	var ctx: Dictionary = context()
	var metadata: Dictionary = {"ring_a":meta("equipment","ring"),"ring_b":meta("equipment","ring"),"skill":meta("skill_gem"),"support":meta("support_gem")}
	var places: Dictionary = {"ring_a":{"kind":"equipment","slot_id":"ring_1"},"ring_b":{"kind":"equipment","slot_id":"ring_2"},"skill":{"kind":"bag","x":0,"y":0},"support":{"kind":"bag","x":1,"y":0}}
	var before: PackedByteArray = var_to_bytes([metadata,places,ctx])
	var swapped: Dictionary = Planner.move(metadata,places,ctx,"ring_a",{"kind":"equipment","slot_id":"ring_2"},7,7)
	expect(swapped.ok and swapped.locations.ring_b.slot_id == "ring_1" and swapped.locations.ring_a.slot_id == "ring_2", "Explicit two-ring swap is atomic")
	expect(swapped.revision == 8 and swapped.displaced_uid == "ring_b", "One candidate revision identifies displaced UID")
	expect(var_to_bytes([metadata,places,ctx]) == before, "Plan does not change source dictionaries")
	swapped.locations.ring_a.slot_id = "weapon"
	expect(var_to_bytes([metadata,places,ctx]) == before, "Returned nested locations do not alias input")
	for destination: Dictionary in [{"kind":"equipment","slot_id":"weapon"},{"kind":"skill_support","group_id":"group_1","index":0},{"kind":"passive_socket","node_id":"58833"},{"kind":"recovery","index":0}]:
		var denied: Dictionary = Planner.move(metadata,places,ctx,"ring_a",destination,7,7)
		expect(not denied.ok and denied.locations.is_empty() and denied.revision == -1, "Type/target/recovery mismatch has no partial candidate")
	var linked: Dictionary = Planner.move(metadata,places,ctx,"skill",{"kind":"skill_main","group_id":"group_1"},7,7)
	expect(linked.ok and linked.locations.skill.group_id == "group_1", "Active gem moves by UID into a stable row")
	var auxiliary: Dictionary = Planner.move(metadata,linked.locations,ctx,"support",{"kind":"skill_support","group_id":"group_1","index":4},8,8)
	expect(auxiliary.ok, "Fifth auxiliary location is structurally supported")
	for bad_revision: Variant in [true,7.0,-1,8,null]:
		expect(not Planner.move(metadata,places,ctx,"skill",{"kind":"skill_main","group_id":"group_1"},7,bad_revision).ok, "Strict stale/invalid revision rejects")
	expect(not Planner.move(metadata,places,ctx,"skill",places.skill,7,7).ok, "No-op does not advance a transaction")
	# A larger displaced armor finds another legal bag area, without overlap.
	var gear: Dictionary = {"small":meta("equipment","body_armour",[1,1]),"large":meta("equipment","body_armour",[2,3]),"block":meta("jewel")}
	var positions: Dictionary = {"small":{"kind":"bag","x":11,"y":7},"large":{"kind":"equipment","slot_id":"body_armour"},"block":{"kind":"bag","x":0,"y":0}}
	var replacement: Dictionary = Planner.move(gear,positions,ctx,"small",{"kind":"equipment","slot_id":"body_armour"},0,0)
	expect(replacement.ok and replacement.locations.large.kind == "bag" and Layout.validate(gear,replacement.locations,ctx).ok, "Displaced larger item finds a legal bag slot")
	# Full bag rejects unequip rather than losing the worn item.
	var full_meta: Dictionary = {"worn":meta("equipment","body_armour",[2,3])}
	var full_places: Dictionary = {"worn":{"kind":"equipment","slot_id":"body_armour"}}
	for y: int in range(8):
		for x: int in range(12):
			var uid: String = "%d_%d" % [x,y]
			full_meta[uid] = meta("jewel")
			full_places[uid] = {"kind":"bag","x":x,"y":y}
	var full_before: PackedByteArray = var_to_bytes(full_places)
	var rejected: Dictionary = Planner.move(full_meta,full_places,ctx,"worn",{"kind":"bag","x":0,"y":0},0,0)
	expect(not rejected.ok and rejected.locations.is_empty() and var_to_bytes(full_places) == full_before, "Full bag preserves all 97 UIDs and positions")
	# Recovery uses a count bound; compacting after a return prevents deadlock
	# when that returned item is later consumed and the total item count shrinks.
	var recover_meta: Dictionary = {}
	var recover_places: Dictionary = {}
	for index: int in range(12):
		var uid: String = "jewel_%d" % index
		recover_meta[uid] = meta("jewel")
		recover_places[uid] = {"kind":"recovery","index":index}
	var recovered: Dictionary = Planner.move(recover_meta,recover_places,context(true),"jewel_0",{"kind":"bag","x":0,"y":0},0,0)
	expect(recovered.ok and recovered.locations.jewel_11.index == 10, "Returning one pending item compacts remaining queue positions")
	recover_meta.erase("jewel_0")
	recovered.locations.erase("jewel_0")
	expect(Layout.validate(recover_meta,recovered.locations,context(true)).ok, "Later consuming the recovered item cannot strand pending items outside N")
	var arranged: Dictionary = Planner.arrange(gear,positions,ctx,0,0)
	expect(arranged.ok and Layout.validate(gear,arranged.locations,ctx).ok and arranged.locations.large == positions.large, "Arrange changes only bag positions, retaining equipment")
	seed(3431)
	var expected: int = randi()
	seed(3431)
	Planner.move(metadata,places,ctx,"skill",{"kind":"skill_main","group_id":"group_1"},7,7)
	expect(randi() == expected, "Candidate planning never consumes global RNG")
	print("Item transfer plan: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
