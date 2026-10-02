extends SceneTree
## Graph, jewel ownership, save safety, and migration regression tests.
## Every fixture uses an isolated path; no real player save is opened.

const Model = preload("res://scripts/build_state.gd")
const Passives = preload("res://scripts/passive_data.gd")
const Jewels = preload("res://scripts/jewel_data.gd")
const SAVE: String = "user://passive_jewel_test.json"
const BAD: String = "user://passive_jewel_bad.json"
const LEGACY: String = "user://passive_jewel_legacy.json"
var checks: int = 0
var failures: int = 0
var changes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_check_graph()
	_check_connectivity()
	_check_jewel_flows()
	_check_rolls()
	_check_backpack()
	_check_full_roll_roundtrip()
	_check_save_safety()
	_check_migration()
	_cleanup()
	print("Passive/jewel invariants: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_graph() -> void:
	var nodes: Dictionary = Passives.get_nodes()
	var edges: Array = Passives.get_edges()
	_expect(nodes.size() >= 150, "Graph has at least 150 nodes")
	_expect(Passives.SECTORS.size() >= 6, "Graph has six distinct sectors")
	_expect(nodes.has(Passives.START_ID), "Graph has stable origin ID")
	var kinds: Dictionary = {"start": 0, "small": 0, "notable": 0, "socket": 0}
	var positions: Dictionary = {}
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		_expect(node.has_all(["id", "name", "type", "position", "stats", "description", "sector", "color"]), "Node metadata complete: " + id)
		_expect(node.id == id and kinds.has(node.type), "Node identity and type valid: " + id)
		kinds[node.type] += 1
		_expect(not positions.has(node.position), "Node occupies distinct position: " + id)
		positions[node.position] = true
		for neighbor: String in Passives.get_neighbors(id):
			_expect(nodes.has(neighbor) and neighbor != id, "Neighbor is valid: " + id + " -> " + neighbor)
			_expect(Passives.get_neighbors(neighbor).has(id), "Adjacency is bidirectional: " + id + " -> " + neighbor)
	_expect(kinds.start == 1 and kinds.small > 100 and kinds.notable >= 12 and kinds.socket >= 12, "Graph mixes small, notable, and socket nodes")
	_expect(edges.size() >= nodes.size(), "Graph includes alternate routes")
	var unique_edges: Dictionary = {}
	for edge: Array in edges:
		_expect(edge.size() == 2 and nodes.has(edge[0]) and nodes.has(edge[1]), "Edge endpoints exist")
		var ids: Array = edge.duplicate()
		ids.sort()
		var key: String = str(ids[0]) + ":" + str(ids[1])
		_expect(not unique_edges.has(key), "Graph has no duplicate edge " + key)
		unique_edges[key] = true
	var visited: Dictionary = _reachable(nodes.keys(), Passives.START_ID)
	_expect(visited.size() == nodes.size(), "Every graph node is reachable from origin")
	for id: String in nodes:
		if nodes[id].type == "socket":
			_expect(nodes[id].stats.is_empty(), "Empty sockets add no innate stats: " + id)


func _check_connectivity() -> void:
	var build := Model.new()
	build.add_xp(1000000000)
	build.changed.connect(_changed)
	changes = 0
	_expect(not build.can_refund(Passives.START_ID) and not build.refund_passive(Passives.START_ID), "Origin cannot be refunded")
	_expect(not build.can_allocate("unknown") and not build.can_refund("unknown"), "Unknown node probes are safe")
	_expect(build.allocate_passive("ember_1_0") and build.allocate_passive("ember_2_0"), "Build a two-node branch")
	var before: Dictionary = build._snapshot()
	var before_changes: int = changes
	_expect(not build.can_refund("ember_1_0") and not build.refund_passive("ember_1_0"), "Bridge refund rejected when child disconnects")
	_expect(build._snapshot() == before and changes == before_changes, "Blocked refund is atomic and silent")
	var alternate: Array[String] = _path_to("ember_2_0", "ember_1_0")
	_expect(not alternate.is_empty(), "Graph contains a genuine alternate route to branch")
	for id: String in alternate:
		if not build.allocated_nodes.has(id):
			_expect(build.allocate_passive(id), "Allocate alternate path: " + id)
	var points: int = build.talent_points
	_expect(build.can_refund("ember_1_0") and build.refund_passive("ember_1_0"), "Alternate route permits former bridge refund")
	_expect(build.allocated_nodes.has("ember_2_0") and build.talent_points == points + 1, "Alternate route preserves child and returns one point")
	_expect(_reachable(build.allocated_nodes, Passives.START_ID).size() == build.allocated_nodes.size(), "All retained allocations remain connected")
	# Allocate all nodes, then repeatedly refund legal leaves/loop members to exercise cycles.
	var all: Array[String] = _breadth_first_order()
	for id: String in all:
		if not build.allocated_nodes.has(id):
			_expect(build.allocate_passive(id), "Full connected graph allocates: " + id)
	_expect(build.allocated_nodes.size() == Passives.get_nodes().size(), "All nodes can be allocated through valid paths")
	var iterations: int = 0
	while build.allocated_nodes.size() > 1 and iterations < all.size():
		var refunded: bool = false
		for id: String in build.allocated_nodes.duplicate():
			if build.can_refund(id):
				_expect(build.refund_passive(id), "Valid cycle/leaf refund succeeds")
				refunded = true
				break
		_expect(refunded, "Nontrivial connected graph always has refundable node")
		if not refunded:
			break
		iterations += 1
	_expect(build.allocated_nodes == [Passives.START_ID], "Repeated safe refunds return to origin")
	_expect(build.talent_points == Model.BASE_TALENT_POINTS + build.level - 1, "Full allocate/refund cycle conserves all points")


func _check_jewel_flows() -> void:
	var build := Model.new()
	build.add_xp(1000000000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 49203
	while build.jewels.size() < 3:
		build.award_jewel(rng)
	var ids: Array = build.jewels.keys()
	var first: String = ids[0]
	var second: String = ids[1]
	var total: int = build.jewels.size()
	var socket_a: String = "ember_3_0"
	var socket_b: String = "grove_3_0"
	var before: Dictionary = build._snapshot()
	_expect(not build.socket_jewel(socket_a, first), "Unallocated socket refuses jewel")
	_expect(not build.socket_jewel("unknown", first), "Unknown socket refuses jewel")
	_expect(not build.socket_jewel(Passives.START_ID, first), "Non-socket node refuses jewel")
	_expect(build._snapshot() == before, "Invalid socket actions preserve every item")
	_allocate_path(build, socket_a)
	_allocate_path(build, socket_b)
	var base: Dictionary = build.get_stats()
	var bonus: Dictionary = build.get_jewel_stats(first)
	_expect(build.socket_jewel(socket_a, first), "Insert owned jewel into allocated socket")
	_expect(build.socketed_jewels.get(socket_a) == first and not build.jewel_inventory.has(first), "Socket takes jewel out of inventory")
	for stat: String in bonus:
		_expect(is_equal_approx(build.get_stats()[stat], base[stat] + bonus[stat]), "Socketed jewel applies live stat: " + stat)
	_expect(not build.socket_jewel(socket_a, first), "Repeated insertion is a no-op")
	_expect(not build.socket_jewel(socket_b, "missing_jewel"), "Unknown jewel cannot be inserted")
	_expect(build.socket_jewel(socket_a, second), "Inventory jewel replaces occupied socket")
	_expect(build.jewel_inventory.has(first) and not build.jewel_inventory.has(second), "Replaced jewel returns to inventory")
	_expect(build.socket_jewel(socket_b, first), "Insert first jewel into second socket")
	_expect(build.socket_jewel(socket_a, first), "Swap jewels directly between occupied sockets")
	_expect(build.socketed_jewels.get(socket_a) == first and build.socketed_jewels.get(socket_b) == second, "Socket swap preserves both unique identities")
	_expect(_ownership_valid(build) and build.jewels.size() == total, "Socket swaps conserve unique jewel ownership")
	_expect(build.remove_jewel(socket_b), "Remove socketed jewel")
	_expect(not build.remove_jewel(socket_b), "Repeated removal cannot duplicate jewel")
	_expect(build.socket_jewel(socket_b, first) and not build.socketed_jewels.has(socket_a), "Move jewel into empty socket atomically")
	_expect(build.remove_jewel(socket_b) and build.get_stats() == base, "Removal reverses only jewel stats")
	_expect(build.socket_jewel(socket_a, second), "Reinsert before socket refund")
	_expect(build.refund_passive(socket_a), "Leaf socket can be refunded with jewel inside")
	_expect(not build.socketed_jewels.has(socket_a) and build.jewel_inventory.has(second), "Socket refund returns jewel safely")
	_allocate_path(build, socket_a)
	_expect(build.socket_jewel(socket_a, second) and build.socket_jewel(socket_b, first), "Populate both sockets before full reset")
	build.refund_talents()
	_expect(build.socketed_jewels.is_empty() and build.jewel_inventory.size() == total, "Full passive reset returns every socketed jewel")
	_expect(_ownership_valid(build), "Reset loses or duplicates no jewels")
	before = build._snapshot()
	build.refund_talents()
	_expect(build._snapshot() == before, "Repeated reset is idempotent")
	# Stress the exact same inventory/socket/refund/reset path repeatedly.
	for i: int in range(12):
		_allocate_path(build, socket_a)
		_expect(build.socket_jewel(socket_a, first), "Repeated flow insertion %d" % i)
		_expect(build.socket_jewel(socket_a, second), "Repeated flow replacement %d" % i)
		build.refund_talents()
		_expect(_ownership_valid(build) and build.jewels.size() == total, "Repeated flow ownership invariant %d" % i)
	# Capacity counts all owned jewels, not only inventory, so returns never overflow.
	while build.jewels.size() < Model.MAX_JEWELS:
		_expect(not build.award_jewel(rng).is_empty(), "Award jewel while capacity remains")
	before = build._snapshot()
	_expect(build.award_jewel(rng).is_empty() and build._snapshot() == before, "Full capacity award rejects atomically")
	_allocate_path(build, socket_a)
	_expect(build.socket_jewel(socket_a, first), "Can insert while total ownership is full")
	before = build._snapshot()
	_expect(build.award_jewel(rng).is_empty() and build._snapshot() == before, "Socketing cannot bypass total-owned cap")
	_expect(build.remove_jewel(socket_a) and _ownership_valid(build), "Full-capacity unsocket never loses jewel")
	_expect(build.socket_jewel(socket_a, first), "Reinsert full-capacity jewel for reset")
	build.refund_talents()
	_expect(build.jewel_inventory.size() == Model.MAX_JEWELS and _ownership_valid(build), "Full-capacity reset returns every jewel")
	_allocate_path(build, socket_a)
	_expect(build.socket_jewel(socket_a, first), "Populate socket before discard validation")
	before = build._snapshot()
	_expect(not build.discard_jewel(first) and not build.discard_jewel("missing"), "Cannot discard socketed or absent jewels")
	_expect(build._snapshot() == before, "Rejected discard is atomic")
	_expect(build.discard_jewel(second), "Unsocketed owned jewel can be discarded")
	_expect(not build.jewels.has(second) and not build.jewel_inventory.has(second) and _ownership_valid(build), "Discard removes exactly one owned instance")
	_expect(not build.discard_jewel(second), "Repeated discard is a no-op")
	var replacement: String = build.award_jewel(rng)
	_expect(not replacement.is_empty() and replacement != second and build.jewels.size() == Model.MAX_JEWELS, "Discard frees capacity without reusing stale identity")


func _check_rolls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42177
	var same_rng := RandomNumberGenerator.new()
	same_rng.seed = 42177
	_expect(Jewels.generate(rng, "jewel_000901") == Jewels.generate(same_rng, "jewel_000901"), "Seeded generation is deterministic")
	var observed_bases: Dictionary = {}
	var observed_rarities: Dictionary = {}
	var observed_affixes: Dictionary = {}
	for i: int in range(1024):
		var id: String = "jewel_%06d" % (i + 1000)
		var jewel: Dictionary = Jewels.generate(rng, id)
		_expect(jewel.id == id and Jewels.validate_instance(jewel), "Generated jewel validates with supplied unique ID")
		observed_bases[jewel.base] = true
		observed_rarities[jewel.rarity] = true
		var rarity: Dictionary = Jewels.RARITIES[jewel.rarity]
		_expect(jewel.affixes.size() >= 1 and jewel.affixes.size() <= int(rarity.max_affixes), "Roll obeys rarity affix cap")
		var groups: Dictionary = {"prefix": 0, "suffix": 0}
		var seen: Dictionary = {}
		var expected_stats: Dictionary = {}
		for affix: Dictionary in jewel.affixes:
			var definition: Dictionary = Jewels.AFFIXES[affix.id]
			_expect(not seen.has(affix.id), "Roll does not repeat affix group")
			seen[affix.id] = true
			observed_affixes[affix.id] = true
			groups[definition.kind] += 1
			_expect(Jewels.BASES[jewel.base][definition.kind + "es"].has(affix.id), "Roll uses base-specific affix pool")
			_expect(float(affix.value) >= float(definition.min) - 0.00001 and float(affix.value) <= float(definition.max) + 0.00001, "Roll obeys value bounds")
			var steps: float = (float(affix.value) - float(definition.min)) / float(definition.step)
			_expect(is_equal_approx(steps, roundf(steps)), "Roll uses allowed value increments")
			expected_stats[definition.stat] = float(expected_stats.get(definition.stat, 0.0)) + float(affix.value)
		_expect(groups.prefix <= rarity.max_prefixes and groups.suffix <= rarity.max_suffixes, "Roll obeys prefix and suffix caps")
		_expect(Jewels.get_stats(jewel) == expected_stats, "Every rolled affix maps to its actual combat stat")
		_expect(not Jewels.display_name(jewel).is_empty() and not Jewels.get_description(jewel).is_empty(), "Rolled jewel has player-readable name and affixes")
	_expect(observed_bases.size() == Jewels.BASES.size() and observed_rarities.size() == Jewels.RARITIES.size(), "Seeded sample exercises every base and rarity")
	_expect(observed_affixes.size() == Jewels.AFFIXES.size(), "Seeded sample exercises every affix")
	var valid: Dictionary = Jewels.starter_jewels()["jewel_000001"]
	var invalid: Dictionary = valid.duplicate(true)
	invalid.affixes[0].value = NAN
	_expect(not Jewels.validate_instance(invalid), "NaN affix rejected")
	invalid = valid.duplicate(true)
	invalid.affixes[0].value = INF
	_expect(not Jewels.validate_instance(invalid), "Infinite affix rejected")
	invalid = valid.duplicate(true)
	invalid.affixes[0].value = true
	_expect(not Jewels.validate_instance(invalid), "Boolean affix rejected")
	invalid = valid.duplicate(true)
	invalid.affixes[0].value = 2.5
	_expect(not Jewels.validate_instance(invalid), "Off-step affix value rejected")
	invalid = valid.duplicate(true)
	invalid.affixes = [{"id": "force", "value": 4.0}, {"id": "vitality", "value": 12.0}]
	_expect(not Jewels.validate_instance(invalid), "Magic jewel cannot have two prefixes")
	invalid = valid.duplicate(true)
	invalid.affixes = [{"id": "tempo", "value": 0.08}, {"id": "stride", "value": 4.0}]
	_expect(not Jewels.validate_instance(invalid), "Magic jewel cannot have two suffixes")
	invalid = valid.duplicate(true)
	invalid.rarity = "rare"
	invalid.affixes = [{"id": "force", "value": 4.0}, {"id": "vitality", "value": 12.0}, {"id": "barrier", "value": 8.0}]
	_expect(not Jewels.validate_instance(invalid), "Rare jewel cannot have three prefixes")
	invalid = valid.duplicate(true)
	invalid.affixes = [{"id": "clarity", "value": 8.0}]
	_expect(not Jewels.validate_instance(invalid), "Affix from another base's pool rejected")
	for malformed: Variant in [null, [], "jewel", {"id": "jewel_000001"}]:
		_expect(not Jewels.validate_instance(malformed), "Malformed jewel instance rejected")
	for malformed_id: String in ["jewel_0", "jewel_1", "jewel_-00001", "jewel_0000010", "unknown", "jewel_1000000000"]:
		invalid = valid.duplicate(true)
		invalid.id = malformed_id
		_expect(not Jewels.validate_instance(invalid), "Malformed jewel identity rejected")


func _check_backpack() -> void:
	var build := Model.new()
	build.changed.connect(_changed)
	changes = 0
	_expect(Model.BACKPACK_COLUMNS == 12 and Model.BACKPACK_ROWS == 8, "Backpack has 12 by 8 cells")
	_expect(_grid_valid(build), "Initial grid exactly covers loose equipment and jewels")
	_expect(build.item_size("item:swift_blade") == Vector2i(1, 3), "Weapon has multi-cell footprint")
	_expect(build.item_size("item:vitality_armor") == Vector2i(2, 3), "Armor has 2 by 3 footprint")
	_expect(build.item_size("jewel:jewel_000001") == Vector2i.ONE, "Jewels use one cell")
	_expect(not build.backpack_positions.has("item:ember_wand") and build.backpack_positions.has("item:swift_blade"), "Equipped gear is outside backpack grid")
	var before: Dictionary = build._snapshot()
	var before_changes: int = changes
	_expect(not build.move_in_backpack("missing", Vector2i.ZERO), "Unknown grid item cannot move")
	_expect(not build.move_in_backpack("item:ember_wand", Vector2i(8, 2)), "Equipped gear cannot move as loose gear")
	for cell: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(12, 0), Vector2i(0, 8), Vector2i(11, 7)]:
		_expect(not build.can_place_in_backpack("item:vitality_armor", cell) and not build.move_in_backpack("item:vitality_armor", cell), "Out-of-bounds item footprint rejected")
	var occupied: Vector2i = build.backpack_positions["item:vitality_armor"]
	_expect(not build.move_in_backpack("item:swift_blade", occupied), "Overlapping item placement rejected")
	_expect(build._snapshot() == before and changes == before_changes, "Invalid grid moves preserve snapshot without signals")
	var key: String = "item:swift_blade"
	var free_cell: Vector2i = _find_free_cell(build, key)
	_expect(free_cell.x >= 0 and build.move_in_backpack(key, free_cell), "Move loose gear to a valid empty location")
	_expect(build.backpack_positions[key] == free_cell and _grid_valid(build), "Moved item occupies requested cells")
	before_changes = changes
	_expect(not build.move_in_backpack(key, free_cell) and changes == before_changes, "Dropping on unchanged cells is a silent no-op")
	_expect(build.equip("swift_blade"), "Equip moved backpack weapon")
	_expect(not build.backpack_positions.has(key) and build.backpack_positions.has("item:ember_wand") and _grid_valid(build), "Weapon swap returns prior weapon to valid cells")
	before = build._snapshot()
	_expect(not build.unequip_to_backpack("weapon", occupied), "Drag-unequip refuses occupied cells")
	_expect(build._snapshot() == before, "Rejected drag-unequip preserves equipped stats and positions")
	free_cell = _find_free_cell(build, key)
	_expect(build.unequip_to_backpack("weapon", free_cell), "Drag-unequip accepts exact empty cells")
	_expect(not build.equipped.has("weapon") and build.backpack_positions.get(key) == free_cell and _grid_valid(build), "Drag-unequip atomically stores item at requested origin")
	for slot: String in Model.EQUIPMENT_SLOTS:
		if build.equipped.has(slot):
			_expect(build.unequip(slot), "Unequip to grid: " + slot)
	_expect(_grid_valid(build) and build.get_backpack_items().size() == 9, "All six equipment items and three jewels fit grid")
	build.auto_sort_backpack()
	before = build._snapshot()
	before_changes = changes
	build.auto_sort_backpack()
	_expect(build._snapshot() == before and changes == before_changes, "Auto-sort is idempotent and does not duplicate items")
	_expect(_grid_valid(build), "Auto-sort respects every footprint")
	build.add_xp(300)
	_allocate_path(build, "ember_3_0")
	var jewel: String = build.jewel_inventory[0]
	_expect(build.socket_jewel("ember_3_0", jewel), "Grid jewel can be inserted")
	_expect(not build.backpack_positions.has("jewel:" + jewel) and _grid_valid(build), "Socketed jewel frees its grid cell")
	_expect(build.remove_jewel("ember_3_0") and build.backpack_positions.has("jewel:" + jewel) and _grid_valid(build), "Removed jewel returns to valid grid location")
	_expect(build.socket_jewel("ember_3_0", jewel), "Reinsert grid jewel before reset")
	build.refund_talents()
	_expect(_grid_valid(build) and build.backpack_positions.has("jewel:" + jewel), "Passive reset restores jewel grid coverage")
	var rng := RandomNumberGenerator.new()
	rng.seed = 792
	while build.jewels.size() < Model.MAX_JEWELS:
		var new_id: String = build.award_jewel(rng)
		_expect(not new_id.is_empty(), "Full loose equipment still leaves space for owned jewel capacity")
		if new_id.is_empty():
			break
	_expect(_grid_valid(build) and build.jewels.size() == Model.MAX_JEWELS, "Full-capacity backpack has valid footprints and coverage")
	var discarded: String = build.jewel_inventory[0]
	_expect(build.discard_jewel(discarded) and not build.backpack_positions.has("jewel:" + discarded), "Discard releases corresponding grid cell")
	_expect(_grid_valid(build), "Discard leaves no orphan grid entry")
	_check_fragmentation_recovery()


func _check_fragmentation_recovery() -> void:
	var build := Model.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	while build.jewels.size() < Model.MAX_JEWELS:
		build.award_jewel(rng)
	# Horizontal jewel barriers leave empty cells, but no empty 2x3 rectangle.
	build.backpack_positions = {"item:swift_blade": Vector2i(0, 0), "item:vitality_armor": Vector2i(1, 0), "item:storm_charm": Vector2i(3, 0)}
	var next: int = 0
	for row: int in [2, 5]:
		for col: int in range(Model.BACKPACK_COLUMNS):
			var key: String = "jewel:" + build.jewel_inventory[next]
			var cell := Vector2i(col, row)
			if build.can_place_in_backpack(key, cell):
				build.backpack_positions[key] = cell
				next += 1
	for row: int in range(Model.BACKPACK_ROWS):
		for col: int in range(Model.BACKPACK_COLUMNS):
			if next >= build.jewel_inventory.size():
				break
			var key: String = "jewel:" + build.jewel_inventory[next]
			var cell := Vector2i(col, row)
			if build.can_place_in_backpack(key, cell):
				build.backpack_positions[key] = cell
				next += 1
	_expect(_grid_valid(build), "Adversarial fragmented grid is a valid starting layout")
	_expect(_find_free_cell(build, "item:guardian_robe") == Vector2i(-1, -1), "Fragmented grid has no direct armor-sized opening")
	var jewels_before: Dictionary = build.jewels.duplicate(true)
	_expect(build.unequip("armor"), "Automatic unequip repacks fragmented grid when necessary")
	_expect(_grid_valid(build) and build.jewels == jewels_before and build.backpack_positions.has("item:guardian_robe"), "Fragmentation recovery preserves every item and jewel")


func _grid_valid(build: Model) -> bool:
	var expected: Array[String] = []
	for item: String in build.inventory:
		if not build.equipped.values().has(item):
			expected.append("item:" + item)
	for jewel: String in build.jewel_inventory:
		expected.append("jewel:" + jewel)
	var actual: Array[String] = build.get_backpack_items()
	if expected.size() != actual.size() or expected.size() != build.backpack_positions.size():
		return false
	var occupied: Dictionary = {}
	for key: String in expected:
		if not actual.has(key) or not build.backpack_positions.has(key):
			return false
		var cell: Vector2i = build.backpack_positions[key]
		var size: Vector2i = build.item_size(key)
		if cell.x < 0 or cell.y < 0 or size.x <= 0 or size.y <= 0 or cell.x + size.x > Model.BACKPACK_COLUMNS or cell.y + size.y > Model.BACKPACK_ROWS:
			return false
		for x: int in range(cell.x, cell.x + size.x):
			for y: int in range(cell.y, cell.y + size.y):
				var coordinate := Vector2i(x, y)
				if occupied.has(coordinate):
					return false
				occupied[coordinate] = key
	return true


func _find_free_cell(build: Model, key: String) -> Vector2i:
	for y: int in range(Model.BACKPACK_ROWS - 1, -1, -1):
		for x: int in range(Model.BACKPACK_COLUMNS - 1, -1, -1):
			var cell := Vector2i(x, y)
			if build.backpack_positions.get(key, Vector2i(-1, -1)) != cell and build.can_place_in_backpack(key, cell):
				return cell
	return Vector2i(-1, -1)


func _check_full_roll_roundtrip() -> void:
	var build := Model.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 61729
	while build.jewels.size() < Model.MAX_JEWELS:
		build.award_jewel(rng)
	build.add_xp(1000000000)
	for socket: String in ["ember_3_0", "grove_3_0", "tide_3_0", "aegis_5_3"]:
		_allocate_path(build, socket)
		build.socket_jewel(socket, build.jewel_inventory.back())
	var original: Dictionary = build._snapshot()
	var original_stats: Dictionary = build.get_stats()
	for iteration: int in range(5):
		_expect(build.save_build(SAVE) == OK, "Full rolled inventory saves without precision loss")
		var restored := Model.new()
		_expect(restored.load_build(SAVE), "Full rolled inventory loads")
		_expect(restored._snapshot() == original and restored.get_stats() == original_stats, "Repeated full-capacity round-trip preserves exact affix floats and stats")
		_expect(_ownership_valid(restored), "Round-trip preserves every grid/jewel location")
		build = restored


func _check_save_safety() -> void:
	var build := Model.new()
	build.add_xp(300)
	_allocate_path(build, "ember_3_0")
	_allocate_path(build, "grove_3_0")
	var rng := RandomNumberGenerator.new()
	rng.seed = 74
	var first: String = build.award_jewel(rng)
	_expect(not first.is_empty() and build.socket_jewel("ember_3_0", first), "Round-trip fixture has rolled socketed jewel")
	_expect(build.save_build(SAVE) == OK, "Save schema v2 with jewels")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	_expect(saved.version == 2 and not saved.has("talents"), "Save v2 uses graph allocation rather than rank talents")
	var restored := Model.new()
	restored.changed.connect(_changed)
	changes = 0
	_expect(restored.load_build(SAVE), "Load schema v2")
	_expect(build._snapshot() == restored._snapshot() and build.get_stats() == restored.get_stats(), "V2 round-trip retains exact rolls, placement, points, and derived stats")
	_expect(changes == 1 and _ownership_valid(restored), "V2 load signals once with valid ownership")
	var candidate: Dictionary = Model.new()._snapshot()
	candidate.allocated_nodes = [Passives.START_ID, "ember_6_0"]
	candidate.talent_points = Model.BASE_TALENT_POINTS - 1
	_reject(restored, candidate, "Disconnected but balanced passive allocation")
	candidate = saved.duplicate(true)
	candidate.allocated_nodes.append(candidate.allocated_nodes.back())
	_reject(restored, candidate, "Duplicate passive ID")
	candidate = saved.duplicate(true)
	candidate.jewel_inventory.append(first)
	_reject(restored, candidate, "Jewel appears in inventory and socket")
	candidate = saved.duplicate(true)
	candidate.jewel_inventory.append(candidate.jewel_inventory[0])
	_reject(restored, candidate, "Duplicate inventory jewel ID")
	candidate = saved.duplicate(true)
	candidate.jewel_inventory.append("missing_jewel")
	_reject(restored, candidate, "Inventory references absent jewel")
	candidate = saved.duplicate(true)
	candidate.jewel_inventory.pop_back()
	_reject(restored, candidate, "Owned jewel orphaned from inventory and sockets")
	candidate = saved.duplicate(true)
	candidate.socketed_jewels["ember_1_0"] = first
	_reject(restored, candidate, "Non-socket node contains jewel")
	candidate = saved.duplicate(true)
	candidate.socketed_jewels["grove_3_0"] = first
	_reject(restored, candidate, "Same jewel assigned to two allocated sockets")
	candidate = saved.duplicate(true)
	candidate.jewels[first].id = "different_id"
	_reject(restored, candidate, "Jewel key and identity mismatch")
	candidate = saved.duplicate(true)
	candidate.jewels[first].base = "unknown_base"
	_reject(restored, candidate, "Unknown jewel base")
	candidate = saved.duplicate(true)
	candidate.jewels[first].rarity = "unique"
	_reject(restored, candidate, "Unsupported jewel rarity")
	candidate = saved.duplicate(true)
	candidate.jewels[first].affixes[0].id = "unknown_affix"
	_reject(restored, candidate, "Unknown affix")
	candidate = saved.duplicate(true)
	candidate.jewels[first].affixes[0].value = 10000000
	_reject(restored, candidate, "Out-of-range affix value")
	candidate = saved.duplicate(true)
	candidate.jewels[first].affixes[0].value = "3"
	_reject(restored, candidate, "Coercible string affix value")
	candidate = saved.duplicate(true)
	candidate.jewels[first].affixes.append(candidate.jewels[first].affixes[0].duplicate())
	_reject(restored, candidate, "Repeated affix ID/group")
	candidate = saved.duplicate(true)
	candidate.next_jewel_id = 1
	_reject(restored, candidate, "Stale jewel identity sequence")
	for field: String in ["allocated_nodes", "jewels", "jewel_inventory", "socketed_jewels", "next_jewel_id", "backpack_positions"]:
		candidate = saved.duplicate(true)
		candidate.erase(field)
		_reject(restored, candidate, "Missing v2 field " + field)
	candidate = saved.duplicate(true)
	var grid_keys: Array = candidate.backpack_positions.keys()
	candidate.backpack_positions[grid_keys[0]] = [-1, 0]
	_reject(restored, candidate, "Negative backpack position")
	candidate = saved.duplicate(true)
	candidate.backpack_positions[grid_keys[0]] = [12, 8]
	_reject(restored, candidate, "Out-of-bounds backpack position")
	candidate = saved.duplicate(true)
	candidate.backpack_positions[grid_keys[0]] = candidate.backpack_positions[grid_keys[1]].duplicate()
	_reject(restored, candidate, "Overlapping backpack footprints")
	candidate = saved.duplicate(true)
	candidate.backpack_positions.erase(grid_keys[0])
	_reject(restored, candidate, "Missing loose item grid position")
	candidate = saved.duplicate(true)
	candidate.backpack_positions["item:ember_wand"] = [10, 7]
	_reject(restored, candidate, "Equipped gear duplicated in grid")
	candidate = saved.duplicate(true)
	candidate.backpack_positions["jewel:" + first] = [11, 7]
	_reject(restored, candidate, "Socketed jewel duplicated in grid")
	for bad_position: Variant in [null, "0,0", [0], [0, 0, 0], [0.5, 0], [true, 0], ["0", 0]]:
		candidate = saved.duplicate(true)
		candidate.backpack_positions[grid_keys[0]] = bad_position
		_reject(restored, candidate, "Malformed backpack coordinate")
	# A failed write cannot destroy an existing valid save.
	var prior: String = FileAccess.get_file_as_string(SAVE)
	build.jewel_inventory.append(first)
	_expect(build.save_build(SAVE) == ERR_INVALID_DATA, "Invalid in-memory jewel ownership cannot save")
	_expect(FileAccess.get_file_as_string(SAVE) == prior, "Rejected jewel save preserves previous bytes")
	var bad_runtime := Model.new()
	bad_runtime.backpack_positions[bad_runtime.backpack_positions.keys()[0]] = "invalid runtime coordinate"
	_expect(bad_runtime.save_build(SAVE) == ERR_INVALID_DATA and FileAccess.get_file_as_string(SAVE) == prior, "Malformed runtime grid cannot crash save or overwrite valid data")


func _check_migration() -> void:
	var legacy: Dictionary = {
		"version": 1,
		"inventory": ["ember_wand", "swift_blade", "guardian_robe", "vitality_armor", "azure_charm", "storm_charm"],
		"equipped": {"weapon": "swift_blade", "charm": "storm_charm"},
		"talents": {"power": 5, "vitality": 3, "focus": 2, "haste": 1, "aegis": 1},
		"skill_slots": ["chain", "meteor", "nova", "dash", "ward"],
		"level": 8, "xp": 7, "talent_points": 0,
	}
	_write(BAD, legacy)
	var build := Model.new()
	_expect(build.load_build(BAD), "Valid v1 save migrates")
	_expect(build.migrated_from_v1 and not build.migration_message.is_empty(), "Migration is explicitly reported to UI")
	_expect(build.level == 8 and build.xp == 7, "Migration retains level and XP")
	_expect(build.equipped == legacy.equipped and build.inventory == legacy.inventory, "Migration retains owned and equipped items")
	_expect(build.skill_slots == legacy.skill_slots, "Migration retains five skill selections")
	_expect(build.talent_points == 12 and build.allocated_nodes == [Passives.START_ID], "All legacy rank points refunded into graph budget")
	_expect(build.socketed_jewels.is_empty() and _ownership_valid(build), "Migration creates coherent starter jewel ownership")
	_expect(_grid_valid(build), "Migration positions all loose gear and starter jewels safely")
	var migrated: Dictionary = build._snapshot()
	_expect(build.load_build(BAD) and build._snapshot() == migrated, "Repeated v1 load cannot duplicate points or jewels")
	_expect(build.save_build(SAVE) == OK, "Migrated build saves as v2")
	var second := Model.new()
	_expect(second.load_build(SAVE) and not second.migrated_from_v1, "Reloaded v2 does not repeat migration notice")
	_expect(second._snapshot() == migrated, "Migration-to-v2 round-trip preserves result")
	var invalid: Dictionary = legacy.duplicate(true)
	invalid.talents.power = 6
	_reject(build, invalid, "V1 over-cap rank")
	invalid = legacy.duplicate(true)
	invalid.talents.power = -1
	_reject(build, invalid, "V1 negative rank")
	invalid = legacy.duplicate(true)
	invalid.talents.focus = 1.5
	_reject(build, invalid, "V1 fractional rank")
	invalid = legacy.duplicate(true)
	invalid.talents.unknown = 0
	_reject(build, invalid, "V1 unknown talent")
	invalid = legacy.duplicate(true)
	invalid.talent_points = 1
	_reject(build, invalid, "V1 inconsistent point budget")
	invalid = legacy.duplicate(true)
	invalid.backpack_positions = {}
	_reject(build, invalid, "V1 rejects hybrid v2 payload")
	invalid = migrated.duplicate(true)
	invalid.version = 1
	invalid.talents = legacy.talents.duplicate()
	_reject(build, invalid, "Tampered version cannot downgrade graph/jewel save")

	# Verify same-path migration is recoverable, including interrupted/conflicting writes.
	_write(LEGACY, legacy)
	var original: String = FileAccess.get_file_as_string(LEGACY)
	var backed_up := Model.new()
	_expect(backed_up.load_build(LEGACY) and backed_up.save_build(LEGACY) == OK, "Same-path migration preserves legacy backup before overwrite")
	_expect(FileAccess.get_file_as_string(LEGACY + ".v1-backup.json") == original, "Legacy backup preserves original bytes")
	_expect(JSON.parse_string(FileAccess.get_file_as_string(LEGACY)).version == 2, "Migration atomically replaces original with schema v2")
	_expect(backed_up.save_build(LEGACY) == OK, "Further v2 save is not blocked by old migration state")
	_write(LEGACY, legacy)
	var conflict := Model.new()
	_expect(conflict.load_build(LEGACY), "Load legacy fixture before conflicting backup")
	_write(LEGACY + ".v1-backup.json", {"unrelated": "must not overwrite"})
	var preserved_backup: String = FileAccess.get_file_as_string(LEGACY + ".v1-backup.json")
	_expect(conflict.save_build(LEGACY) != OK, "Conflicting backup blocks migration overwrite")
	_expect(FileAccess.get_file_as_string(LEGACY) == original and FileAccess.get_file_as_string(LEGACY + ".v1-backup.json") == preserved_backup, "Backup conflict preserves original and existing backup")
	DirAccess.remove_absolute(LEGACY + ".v1-backup.json")
	var changed_source := Model.new()
	_expect(changed_source.load_build(LEGACY), "Load legacy fixture before external modification")
	var external: Dictionary = legacy.duplicate(true)
	external.xp = 8
	_write(LEGACY, external)
	var external_bytes: String = FileAccess.get_file_as_string(LEGACY)
	_expect(changed_source.save_build(LEGACY) != OK and FileAccess.get_file_as_string(LEGACY) == external_bytes, "Changed migration source is never overwritten")


func _path_to(target: String, excluded: String = "") -> Array[String]:
	var previous: Dictionary = {Passives.START_ID: ""}
	var queue: Array[String] = [Passives.START_ID]
	var cursor: int = 0
	while cursor < queue.size():
		var id: String = queue[cursor]
		cursor += 1
		if id == target:
			var path: Array[String] = []
			while id != "":
				path.push_front(id)
				id = previous[id]
			return path
		for neighbor: String in Passives.get_neighbors(id):
			if neighbor != excluded and not previous.has(neighbor):
				previous[neighbor] = id
				queue.append(neighbor)
	return []


func _breadth_first_order() -> Array[String]:
	var result: Array[String] = [Passives.START_ID]
	var visited: Dictionary = {Passives.START_ID: true}
	var cursor: int = 0
	while cursor < result.size():
		var id: String = result[cursor]
		cursor += 1
		for neighbor: String in Passives.get_neighbors(id):
			if not visited.has(neighbor):
				visited[neighbor] = true
				result.append(neighbor)
	return result


func _reachable(allowed: Array, origin: String) -> Dictionary:
	var result: Dictionary = {origin: true}
	var queue: Array[String] = [origin]
	var cursor: int = 0
	while cursor < queue.size():
		var id: String = queue[cursor]
		cursor += 1
		for neighbor: String in Passives.get_neighbors(id):
			if allowed.has(neighbor) and not result.has(neighbor):
				result[neighbor] = true
				queue.append(neighbor)
	return result


func _allocate_path(build: Model, target: String) -> void:
	for id: String in _path_to(target):
		if not build.allocated_nodes.has(id):
			_expect(build.allocate_passive(id), "Allocate socket access path " + id)


func _ownership_valid(build: Model) -> bool:
	var seen: Dictionary = {}
	for id: String in build.jewel_inventory:
		if seen.has(id) or not build.jewels.has(id):
			return false
		seen[id] = true
	for socket: String in build.socketed_jewels:
		var id: String = build.socketed_jewels[socket]
		if seen.has(id) or not build.jewels.has(id) or not build.allocated_nodes.has(socket):
			return false
		if Passives.get_nodes()[socket].type != "socket":
			return false
		seen[id] = true
	return seen.size() == build.jewels.size() and _grid_valid(build)


func _reject(build: Model, candidate: Dictionary, description: String) -> void:
	var before: Dictionary = build._snapshot()
	var before_stats: Dictionary = build.get_stats()
	var before_changes: int = changes
	var migrated: bool = build.migrated_from_v1
	_write(BAD, candidate)
	_expect(not build.load_build(BAD), description + " rejected")
	_expect(build._snapshot() == before and build.get_stats() == before_stats and changes == before_changes and build.migrated_from_v1 == migrated, description + " leaves live build unchanged")


func _write(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Save fixture file opens")
	if file:
		file.store_string(JSON.stringify(value))
		file.close()


func _changed() -> void:
	changes += 1


func _cleanup() -> void:
	for path: String in [SAVE, SAVE + ".tmp", BAD, LEGACY, LEGACY + ".tmp", LEGACY + ".v1-backup.json", LEGACY + ".v1-backup.json.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
