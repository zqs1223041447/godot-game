class_name SpatialTargetIndex
extends RefCounted
## Conservative broadphase only: callers retain their exact collision/separation test.
## Values are original array indices, sorted ascending; IDs are never deduplicated.
## Rebuild after structural array changes. Mutate pos/radius, then update that index.
const DEFAULT_CELL_SIZE: float = 128.0
const MAX_CELLS_PER_OPERATION: int = 4096
const MAX_CELL_COORDINATE: int = 1048576
const ROUNDING_MARGIN: float = 0.01
var _cell_size: float = DEFAULT_CELL_SIZE
var _targets: Array[Dictionary] = []
var _cells: Dictionary = {}
var _memberships: Array[Array] = []
var _aliases: Array[Array] = []
var _overflow: Dictionary = {}


func _init(cell_size: float = DEFAULT_CELL_SIZE) -> void:
	if is_finite(cell_size) and cell_size > 0.0:
		_cell_size = cell_size


func rebuild(targets: Array[Dictionary]) -> void:
	_targets = targets
	_cells.clear()
	_memberships.clear()
	_aliases.clear()
	_overflow.clear()
	# IDs are only a cheap bucket for identity checks, never the spatial result key.
	# Same-reference dictionaries necessarily have the same ID at rebuild time.
	var identity_buckets: Dictionary = {}
	for index: int in range(_targets.size()):
		_memberships.append([])
		var bucket: int = hash(_targets[index].get("id", null))
		var representatives: Array = identity_buckets.get(bucket, [])
		var aliases: Array = []
		for representative: int in representatives:
			if is_same(_targets[index], _targets[representative]):
				aliases = _aliases[representative]
				break
		if aliases.is_empty():
			representatives.append(index)
			identity_buckets[bucket] = representatives
		aliases.append(index)
		_aliases.append(aliases)
		_insert(index)


func update(index: int) -> void:
	if _targets.size() != _memberships.size():
		rebuild(_targets)
		return
	if index < 0 or index >= _targets.size():
		return
	# One mutated Dictionary can occupy several positions in the source array.
	# Updating all aliases preserves the old sequential all-target scan semantics.
	for alias_index: int in _aliases[index]:
		_remove(alias_index)
		_insert(alias_index)


func query_aabb(rect: Rect2) -> Array[int]:
	if _targets.size() != _memberships.size():
		rebuild(_targets)
	var bounds: Array[int] = _cell_bounds(rect)
	if bounds.is_empty():
		return _all_indices()
	var found: Dictionary = _overflow.duplicate()
	for x: int in range(bounds[0], bounds[2] + 1):
		for y: int in range(bounds[1], bounds[3] + 1):
			for index: int in _cells.get(Vector2i(x, y), []):
				found[index] = true
	var result: Array[int] = []
	result.assign(found.keys())
	result.sort()
	return result


func query_circle(center: Vector2, radius: float) -> Array[int]:
	if not center.is_finite() or not is_finite(radius) or radius < 0.0:
		return _all_indices()
	return query_aabb(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))


func query_sweep(start: Vector2, end: Vector2, expansion_radius: float) -> Array[int]:
	if not start.is_finite() or not end.is_finite() or not is_finite(expansion_radius) or expansion_radius < 0.0:
		return _all_indices()
	# Vector2 dot/length operations use engine real_t precision. A tiny broadphase
	# cushion also covers near-tangent quadratic cancellation on long sweeps.
	# Neither this cushion nor cell bounds change the exact narrowphase radius.
	var margin: float = maxf(ROUNDING_MARGIN, start.distance_to(end) * 0.001)
	var expansion: Vector2 = Vector2.ONE * (expansion_radius + margin)
	var lower: Vector2 = start.min(end) - expansion
	var upper: Vector2 = start.max(end) + expansion
	return query_aabb(Rect2(lower, upper - lower))


func _all_indices() -> Array[int]:
	var result: Array[int] = []
	result.assign(range(_targets.size()))
	return result


func _insert(index: int) -> void:
	var target: Dictionary = _targets[index]
	var position_value: Variant = target.get("pos")
	var radius_value: Variant = target.get("radius", 0.0)
	if not position_value is Vector2 or not (radius_value is int or radius_value is float):
		_overflow[index] = true
		return
	var position: Vector2 = position_value
	var radius: float = float(radius_value)
	if not position.is_finite() or not is_finite(radius) or radius < 0.0:
		_overflow[index] = true
		return
	var bounds: Array[int] = _cell_bounds(Rect2(position - Vector2.ONE * radius, Vector2.ONE * radius * 2.0))
	if bounds.is_empty():
		_overflow[index] = true
		return
	for x: int in range(bounds[0], bounds[2] + 1):
		for y: int in range(bounds[1], bounds[3] + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell):
				_cells[cell] = []
			_cells[cell].append(index)
			_memberships[index].append(cell)


func _remove(index: int) -> void:
	_overflow.erase(index)
	for cell: Vector2i in _memberships[index]:
		_cells[cell].erase(index)
		if _cells[cell].is_empty():
			_cells.erase(cell)
	_memberships[index].clear()


func _cell_bounds(rect: Rect2) -> Array[int]:
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x < 0.0 or rect.size.y < 0.0:
		return []
	var lower: Vector2 = rect.position
	var upper: Vector2 = rect.end
	if not upper.is_finite():
		return []
	# Cover float32 coordinate rounding at cell borders, including zero-size boxes.
	var magnitude: float = maxf(maxf(absf(lower.x), absf(lower.y)), maxf(absf(upper.x), absf(upper.y)))
	var margin: float = maxf(ROUNDING_MARGIN, magnitude * 0.000001)
	var min_x: float = floor((float(lower.x) - margin) / _cell_size)
	var min_y: float = floor((float(lower.y) - margin) / _cell_size)
	var max_x: float = floor((float(upper.x) + margin) / _cell_size)
	var max_y: float = floor((float(upper.y) + margin) / _cell_size)
	if not is_finite(min_x) or not is_finite(min_y) or not is_finite(max_x) or not is_finite(max_y):
		return []
	if min_x < -MAX_CELL_COORDINATE or min_y < -MAX_CELL_COORDINATE or max_x > MAX_CELL_COORDINATE or max_y > MAX_CELL_COORDINATE:
		return []
	if (max_x - min_x + 1.0) * (max_y - min_y + 1.0) > MAX_CELLS_PER_OPERATION:
		return []
	return [int(min_x), int(min_y), int(max_x), int(max_y)]
