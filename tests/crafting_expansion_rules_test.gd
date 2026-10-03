extends SceneTree
const Craft = preload("res://scripts/items/crafting_rules.gd")
const Expand = preload("res://scripts/items/crafting_expansion_rules.gd")
const Catalog = preload("res://scripts/items/equipment_catalog.gd")
var checks := 0
var failures := 0
var plans := 0
var budget_rows: Array = []
func _initialize() -> void:
	call_deferred("_run")
func expect(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(why)
func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2041
	for base_id: String in Catalog.all_base_ids():
		for level: int in range(1, 31):
			var normal: Dictionary = {"id": "gear_000123", "base_id": base_id, "rarity": "normal", "item_level": level, "affixes": []}
			for rarity: String in ["normal", "magic", "rare"]:
				var source: Dictionary = normal.duplicate(true)
				if rarity != "normal":
					source = Craft.operation_plan(source, "enchant", 107).instance
					if rarity == "rare":
						source = Craft.operation_plan(source, "elevate", 210).instance
				for operation: String in Expand.OPERATIONS:
					var before: PackedByteArray = var_to_bytes(source)
					var q: Dictionary = Craft.operation_quote(source, operation)
					if not q.ok:
						expect(not Expand.OPERATIONS[operation].rarities.has(rarity) or operation == "augment", "Only ineligible rarity/full capacity rejects")
						continue
					expect(q.instance.is_empty() and q.definition.is_empty(), "Quote contains no rolled result")
					for seed_value: int in [-3, 0, 741]:
						var plan: Dictionary = Craft.operation_plan(source, operation, seed_value)
						plans += 1
						expect(plan.ok, "%s/%s/%s result" % [base_id, rarity, operation])
						if not plan.ok:
							continue
						var item: Dictionary = plan.instance
						expect(Catalog.validate_instance(item), "Legal full item")
						expect(Catalog.validate_instance(JSON.parse_string(JSON.stringify(item))), "JSON-valid result")
						expect(item.id == source.id and item.base_id == source.base_id and item.item_level == source.item_level, "Stable identity/base/level")
						expect(plan.definition == Catalog.definition(item), "Same-source modifiers/local weapon definition")
						expect(plan == Craft.operation_plan(source, operation, seed_value), "Deterministic plan")
						expect(var_to_bytes(source) == before, "Detached source")
						expect(plan.cost == q.cost and plan.materials.is_empty() and not plan.consumes_item, "Exact quoted economics")
						expect(int(plan.cost[Craft.MATERIAL_ID]) > _yield(item) - _yield(source), "Strict decrease of wallet+salvage potential")
						if operation in ["augment", "elevate"]:
							for i: int in range(source.affixes.size()):
								expect(var_to_bytes(source.affixes[i]) == var_to_bytes(item.affixes[i]), "Retained affix byte identity/order")
						if operation == "augment":
							expect(item.affixes.size() == source.affixes.size() + 1, "Exactly one new affix")
				# Conservative maximum tier bound covers every legal result, not only sampled rolls.
				var highest: int = 0
				for family_id: String in Catalog.all_affix_ids():
					if Catalog.family_eligible(family_id, base_id):
						for tier: Dictionary in Catalog.affix_definition(family_id).tiers:
							if int(tier.level) <= level and int(tier.weight) > 0:
								highest = maxi(highest, int(tier.tier))
				var ceilings: Dictionary = {"enchant": 1 + 2 * highest, "elevate": 3 + 6 * highest - 2, "augment": highest, "reforge": (1 + 2 * highest - 2) if rarity == "magic" else (3 + 6 * highest - 7)}
				for operation: String in Expand.OPERATIONS:
					var rule: Dictionary = Expand.OPERATIONS[operation]
					if not rule.rarities.has(rarity):
						continue
					var price: int = int(rule.cost_by_rarity[rarity]) if rule.has("cost_by_rarity") else int(rule.cost)
					expect(price > int(ceilings[operation]), "All-results material bound")
					budget_rows.append({"base": base_id, "ilvl": level, "rarity": rarity, "operation": operation, "cost": price, "max_salvage_gain_bound": ceilings[operation], "min_material_sink": price - int(ceilings[operation])})
	# Schema can accept every output without adding persistent operation IDs.
	var normal: Dictionary = {"id": "gear_000123", "base_id": Catalog.all_base_ids()[0], "rarity": "normal", "item_level": 30, "affixes": []}
	for invalid_seed: Variant in [true, 0.0, "1", null, [], {}]:
		expect(not Craft.operation_plan(normal, "enchant", invalid_seed).ok, "Reject non-int seed")
	for bad: Variant in [true, 2, {}, null, "missing"]:
		expect(not Craft.operation_quote(normal, bad).ok, "Reject malformed operation")
	var full: Dictionary = Craft.operation_plan(Craft.operation_plan(normal, "enchant", 1).instance, "elevate", 1).instance
	while full.affixes.size() < 6:
		full = Craft.operation_plan(full, "augment", 1).instance
	expect(not Craft.operation_quote(full, "augment").ok, "Full prefix/suffix item rejects before seed")
	seed(4545)
	var expected: int = randi()
	seed(4545)
	Craft.operation_plan(normal, "enchant", 35)
	expect(randi() == expected, "Global RNG untouched")
	expect(Craft.seed_rules_version("recalibrate") == "original-crafting-prototype-v1", "Legacy seed stays identical")
	var file := FileAccess.open("user://crafting-expansion-budget.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": budget_rows, "all_results_bound": true}, "\t"))
	file.close()
	print("Crafting expansion: %d plans, %d budget rows; %d checks, %d failures" % [plans, budget_rows.size(), checks, failures])
	quit(0 if failures == 0 else 1)
func _yield(item: Dictionary) -> int:
	return 0 if item.rarity == "normal" else int(Craft.salvage_quote(item).materials[Craft.MATERIAL_ID])
