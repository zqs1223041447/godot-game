extends RefCounted
## Once-only death, reserved lineage budgets, and deferred FIFO descendants.
const Catalog = preload("res://docs/qa/v075-integration-tests/frozen/catalog.gd")
const MAX_GENERATION: int = 3
const MAX_DESCENDANTS: int = 12
const MAX_QUEUE: int = 64
const MAX_CHILDREN_PER_DEATH: int = 6
var templates: Dictionary = {}
var validation_errors: Array[String] = []
var queue: Array[Dictionary] = []
var roots: Dictionary = {}
var trace: Array[Dictionary] = []
var next_id: int = 0

func _init(source: Dictionary = Catalog.TEMPLATES) -> void:
	validation_errors = Catalog.validate_templates(source)
	if validation_errors.is_empty():
		templates = source.duplicate(true)

func reset() -> void:
	queue.clear()
	roots.clear()
	trace.clear()
	# Never reuse identities within this runtime, including across reset.

func cancel_pending(reason: String) -> void:
	if not queue.is_empty():
		_record({"type": "cancelled", "reason": reason, "count": queue.size()})
	queue.clear()

func create_root(template_id: String, wave: int, position: Vector2, context: String = "ordinary",
		rarity: String = "", mechanisms: Array = [], rewards: bool = true) -> Dictionary:
	if templates.is_empty():
		return {}
	next_id += 1
	var enemy: Dictionary = Catalog.make_enemy(next_id, template_id, wave, position, context, rarity, mechanisms, templates)
	if enemy.is_empty():
		return {}
	enemy.reward_eligible = rewards
	roots[enemy.id] = {"reserved": 0, "processed": {}}
	return enemy

func process_death(enemy: Dictionary) -> Dictionary:
	if float(enemy.get("health", 1.0)) > 0.0 or bool(enemy.get("death_processed", false)):
		return {"processed": false, "reward": false, "queued": 0}
	var root_id: int = int(enemy.get("root_id", 0))
	var enemy_id: int = int(enemy.get("id", 0))
	if not roots.has(root_id) or roots[root_id].processed.has(enemy_id):
		return {"processed": false, "reward": false, "queued": 0}
	enemy.death_processed = true
	roots[root_id].processed[enemy_id] = true
	var result: Dictionary = {"processed": true, "reward": bool(enemy.get("reward_eligible", false)), "queued": 0}
	var child_value: Variant = enemy.get("death_spawns", [])
	if not child_value is Array:
		_record({"type": "rejected", "reason": "invalid_child_list", "parent_id": enemy_id, "count": 0})
		return result
	var children: Array = child_value
	if children.is_empty():
		return result
	var total: int = 0
	for child: Variant in children:
		if not child is Dictionary or not child.get("template") is String or not child.get("count") is int or int(child.count) <= 0:
			_record({"type": "rejected", "reason": "invalid_child_template", "parent_id": enemy_id, "count": 0})
			return result
		total += int(child.count)
	var generation: int = int(enemy.get("generation", 0)) + 1
	var reason: String = ""
	if not roots.has(root_id):
		reason = "unknown_lineage"
	elif generation > MAX_GENERATION:
		reason = "generation_budget"
	elif total < 1 or total > MAX_CHILDREN_PER_DEATH:
		reason = "per_death_budget"
	elif int(roots[root_id].reserved) + total > MAX_DESCENDANTS:
		reason = "lineage_budget"
	elif queue.size() + total > MAX_QUEUE:
		reason = "queue_capacity"
	else:
		for child: Dictionary in children:
			if not templates.has(str(child.get("template", ""))) or str(templates[str(child.template)].rarity) not in Catalog.ORDINARY_RARITIES or int(child.count) <= 0:
				reason = "invalid_child_template"
				break
	if not reason.is_empty():
		_record({"type": "rejected", "reason": reason, "parent_id": enemy.id, "count": total})
		return result
	roots[root_id].reserved = int(roots[root_id].reserved) + total
	var index: int = 0
	for child: Dictionary in children:
		for count: int in range(int(child.count)):
			var offset: Vector2 = Vector2.RIGHT.rotated(TAU * index / maxi(1, total)) * 30.0
			queue.append({"template": str(child.template), "root_id": root_id, "generation": generation,
				"wave": int(enemy.get("wave", 1)), "pos": Vector2(enemy.pos) + offset, "parent_id": int(enemy.id)})
			index += 1
	result.queued = total
	_record({"type": "queued", "parent_id": enemy.id, "count": total, "generation": generation})
	return result

func drain(available: int, arena: Rect2) -> Array[Dictionary]:
	var spawned: Array[Dictionary] = []
	for index: int in range(mini(maxi(0, available), queue.size())):
		var request: Dictionary = queue.pop_front()
		next_id += 1
		var enemy: Dictionary = Catalog.make_enemy(next_id, request.template, int(request.wave), request.pos, "death_child", "", [], templates)
		if enemy.is_empty():
			_record({"type": "rejected", "reason": "template_changed", "parent_id": request.parent_id, "count": 1})
			continue
		var margin: float = float(enemy.radius)
		enemy.pos = Vector2(clampf(float(enemy.pos.x), arena.position.x + margin, arena.end.x - margin),
			clampf(float(enemy.pos.y), arena.position.y + margin, arena.end.y - margin))
		enemy.root_id = request.root_id
		enemy.generation = request.generation
		enemy.parent_id = request.parent_id
		enemy.reward_eligible = false
		enemy.xp_reward = 0
		spawned.append(enemy)
		_record({"type": "spawned", "parent_id": request.parent_id, "template": request.template, "generation": request.generation})
	return spawned

func collect_lineages(enemies: Array[Dictionary]) -> void:
	var live: Dictionary = {}
	for enemy: Dictionary in enemies:
		if float(enemy.get("health", 0.0)) > 0.0:
			live[int(enemy.get("root_id", 0))] = true
	for request: Dictionary in queue:
		live[int(request.root_id)] = true
	for root_id: int in roots.keys():
		if not live.has(root_id):
			roots.erase(root_id)

func _record(event: Dictionary) -> void:
	trace.append(event)
	if trace.size() > 48:
		trace.pop_front()
