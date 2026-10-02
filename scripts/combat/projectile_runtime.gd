class_name ProjectileRuntime
extends RefCounted
## Pure-data carrier simulation. Events are resolved after movement, never recursively.
## Each segment is clipped at a semantic boundary; hits are sorted by time of impact.
const Recipes = preload("res://scripts/combat/combat_data.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const TargetIndex = preload("res://scripts/combat/spatial_target_index.gd")
const EPS: float = 0.000001
const MAX_GENERATION: int = 1
var next_projectile_id: int = 1
var next_cast_id: int = 1
var _sequence: int = 0
# Reference switch for differential tests/profiling; not a player-facing setting.
var use_spatial_index: bool = true
var use_cached_work_order: bool = true
var last_work_sorts: int = 0
var last_work_sort_skips: int = 0
var last_work_order_checks: int = 0
var last_candidate_visits: int = 0
var last_full_scan_visits: int = 0
var last_contact_queries: int = 0
var last_indexed_queries: int = 0
var _target_index = TargetIndex.new()
var _in_advance: bool = false
var _index_active: bool = false


func new_cast() -> int:
	var value: int = next_cast_id
	next_cast_id += 1
	return value


func make_projectile(origin: Vector2, direction: Vector2, spec: Dictionary,
		payload: Dictionary, snapshot: Dictionary, cast_id: int, color: Color,
		parent_id: int = 0, root_id: int = 0, generation: int = 0) -> Dictionary:
	var id: int = next_projectile_id
	next_projectile_id += 1
	var heading: Vector2 = direction.normalized() if direction.length_squared() > EPS else Vector2.RIGHT
	var shot: Dictionary = {
		"id": id, "cast_id": cast_id, "parent_id": parent_id, "root_id": id if root_id == 0 else root_id,
		"generation": generation, "skill_id": str(payload.get("skill_id", "")),
		"role": str(spec.get("role", "ordinary")), "state": "outbound", "active": true, "end_reason": "",
		"pos": origin, "previous": origin, "velocity": heading * float(spec.get("speed", 600.0)),
		"speed": float(spec.get("speed", 600.0)), "range": float(spec.get("range", 650.0)),
		"distance": 0.0, "age": 0.0, "lifetime": float(spec.get("lifetime", 1.7)),
		"life": float(spec.get("lifetime", 1.7)), "radius": float(spec.get("radius", 5.5)),
		"pierce": int(spec.get("pierce", 0)), "slow": float(spec.get("slow", 0.0)),
		"split": bool(spec.get("split", false)), "color": color,
		"payload": payload.duplicate(true), "snapshot": snapshot.duplicate(true),
		"recipe": snapshot.get("tornado_recipe", Recipes.TORNADO).duplicate(true),
		"hit_ids": [], "hit_ledger": {}, "fired": {}, "return_center": Vector2.ZERO,
		"damage": float(Damage.resolve(payload, snapshot.get("modifiers", [])).total),
	}
	return shot


func spawn_tornado(shots: Array[Dictionary], origin: Vector2, heading: Vector2,
		snapshot: Dictionary, max_projectiles: int, requested_count: int = -1) -> int:
	var recipe: Dictionary = snapshot.get("tornado_recipe", Recipes.TORNADO)
	var count: int = clampi(requested_count if requested_count >= 0 else int(recipe.parent_count) + int(snapshot.get("projectile_count", 0)), 1, 9)
	# Cast admission is all-or-none so budget pressure never silently changes n.
	if shots.size() + count > max_projectiles:
		return 0
	var payload: Dictionary = Recipes.event_packet(snapshot, "tornado", "parent")
	if payload.is_empty():
		return 0
	var cast_id: int = new_cast()
	for index: int in range(count):
		var angle: float = (index - (count - 1) * 0.5) * float(recipe.spread)
		var direction: Vector2 = heading.rotated(angle).normalized()
		shots.append(make_projectile(origin + direction * 19.0, direction, recipe.parent,
			payload, snapshot, cast_id, Color("a6e8aa")))
	return count


func advance(shots: Array[Dictionary], delta: float, targets: Array[Dictionary],
		owner_center: Vector2, max_projectiles: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	last_work_sorts = 0
	last_work_sort_skips = 0
	last_work_order_checks = 0
	last_candidate_visits = 0
	last_full_scan_visits = 0
	last_contact_queries = 0
	last_indexed_queries = 0
	_in_advance = false
	_index_active = false
	if delta <= 0.0 or not is_finite(delta):
		return events
	_in_advance = true
	_index_active = use_spatial_index
	if _index_active:
		_target_index.rebuild(targets)
	var work: Array[Dictionary] = []
	for shot: Dictionary in shots:
		work.append(_schedule(shot, delta, 0.0, targets))
	var active_count: int = shots.size()
	var work_dirty: bool = true
	var work_order_safe: bool = false
	while not work.is_empty():
		# Keep the historical comparator and every-pop fallback. Only a proven
		# strict order survives pops unchanged; every append invalidates the proof.
		if not use_cached_work_order or work_dirty or not work_order_safe:
			work.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if not is_equal_approx(float(a.at), float(b.at)):
					return float(a.at) < float(b.at)
				if int(a.priority) != int(b.priority):
					return int(a.priority) < int(b.priority)
				return int(a.shot.id) < int(b.shot.id))
			last_work_sorts += 1
			if use_cached_work_order and work_dirty:
				last_work_order_checks += 1
				work_order_safe = _work_order_is_strict(work)
		else:
			last_work_sort_skips += 1
		work_dirty = false
		var job: Dictionary = work.pop_front()
		var shot: Dictionary = job.shot
		var travel: float = float(job.travel)
		var offset: float = float(job.offset)
		var remaining: float = float(job.remaining)
		var start: Vector2 = shot.pos
		var end: Vector2 = start + Vector2(shot.velocity) * travel
		shot.previous = start
		var consumed: bool = false
		for contact: Dictionary in job.contacts:
			var target_id: int = int(contact.id)
			shot.hit_ledger["%s:%d" % [shot.state, target_id]] = true
			shot.hit_ids.append(target_id)
			var hit_time: float = float(contact.t) * travel
			var hit_position: Vector2 = start.lerp(end, float(contact.t))
			_event(events, "hit", shot, offset + hit_time, {"target_id": target_id,
				"pos": hit_position, "payload": shot.payload, "snapshot": shot.snapshot, "slow": shot.slow,
				"direction": Vector2(shot.velocity).normalized(), "color": shot.color,
				"age": float(shot.age) + hit_time})
			if int(shot.pierce) == 0:
				travel = hit_time
				end = hit_position
				consumed = true
				break
			if int(shot.pierce) > 0:
				shot.pierce = int(shot.pierce) - 1
		shot.pos = end
		shot.age = float(shot.age) + travel
		shot.life = maxf(0.0, float(shot.lifetime) - float(shot.age))
		shot.distance = float(shot.distance) + float(shot.speed) * travel
		offset += travel
		remaining = maxf(0.0, remaining - travel)
		if consumed:
			_finish(shot, "hit_consumed", events, offset)
		elif float(shot.life) <= EPS:
			# The immutable lifetime ceiling wins a range/split/return tie.
			_event(events, "lifetime_expired", shot, offset)
			_natural_end(shot, "lifetime_expired", events, offset)
		elif shot.state == "outbound" and float(shot.distance) >= float(shot.range) - EPS:
			_event(events, "range_reached", shot, offset)
			if bool(shot.split):
				var child_count: int = int(shot.recipe.child_count)
				var child_payload: Dictionary = Recipes.event_packet(shot.snapshot, str(shot.skill_id), "child")
				if child_payload.is_empty() or int(shot.generation) >= MAX_GENERATION or active_count - 1 + child_count > max_projectiles:
					_event(events, "spawn_rejected", shot, offset, {"reason": "budget_or_generation"})
					_finish(shot, "budget_cancelled", events, offset)
				else:
					_event(events, "split", shot, offset, {"count": child_count})
					_finish(shot, "split_consumed", events, offset)
					for index: int in range(child_count):
						var direction: Vector2 = Vector2(shot.velocity).normalized().rotated(TAU * index / child_count)
						var child: Dictionary = make_projectile(shot.pos, direction, shot.recipe.child,
							child_payload, shot.snapshot, int(shot.cast_id), Color("70dfed"),
							int(shot.id), int(shot.root_id), int(shot.generation) + 1)
						shots.append(child)
						if remaining > EPS:
							work.append(_schedule(child, remaining, offset, targets))
							work_dirty = true
						active_count += 1
						_event(events, "spawned", child, offset)
			elif _effect(shot, "return_on_range", "range_reached"):
				shot.state = "returning"
				shot.return_center = owner_center
				var direction: Vector2 = owner_center - Vector2(shot.pos)
				if direction.length_squared() <= EPS:
					direction = -Vector2(shot.velocity)
				shot.velocity = direction.normalized() * float(shot.speed)
				_event(events, "return_started", shot, offset, {"aim_center": owner_center})
			else:
				_natural_end(shot, "range_consumed", events, offset)
		if not bool(shot.active):
			active_count -= 1
		elif remaining > EPS:
			work.append(_schedule(shot, remaining, offset, targets))
			work_dirty = true
	var survivors: Array[Dictionary] = []
	for shot: Dictionary in shots:
		if bool(shot.active):
			survivors.append(shot)
	shots.assign(survivors)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.time), float(b.time)):
			return float(a.time) < float(b.time)
		return int(a.sequence) < int(b.sequence))
	_in_advance = false
	_index_active = false
	return events


static func _work_order_is_strict(work: Array[Dictionary]) -> bool:
	# is_equal_approx is not transitive. Distinct near-equal times could reorder
	# under repeated sorts, so do not cache any batch containing that ambiguity.
	# Exact equal times are safe: priority then unique shot ID is a strict key.
	var ids: Dictionary = {}
	var times: Array[float] = []
	for job: Dictionary in work:
		var at: float = float(job.at)
		var id: int = int(job.shot.id)
		if not is_finite(at) or ids.has(id):
			return false
		ids[id] = true
		times.append(at)
	times.sort()
	for index: int in range(1, times.size()):
		var previous: float = times[index - 1]
		var current: float = times[index]
		if previous != current and (is_equal_approx(previous, current) or is_equal_approx(current, previous)):
			return false
	return true


func _schedule(shot: Dictionary, remaining: float, offset: float, targets: Array[Dictionary]) -> Dictionary:
	var life_left: float = maxf(0.0, float(shot.lifetime) - float(shot.age))
	var range_left: float = INF
	if shot.state == "outbound":
		range_left = maxf(0.0, float(shot.range) - float(shot.distance)) / maxf(EPS, float(shot.speed))
	var travel: float = minf(remaining, minf(life_left, range_left))
	var start: Vector2 = shot.pos
	var contacts: Array[Dictionary] = _contacts(shot, start, start + Vector2(shot.velocity) * travel, targets)
	# A contact exactly at the expiry deadline is outside this carrier's active interval.
	if life_left <= EPS:
		contacts.clear()
	elif life_left <= travel + EPS:
		contacts = contacts.filter(func(c: Dictionary) -> bool: return float(c.t) < 1.0 - EPS)
	var priority: int = 0 if life_left <= travel + EPS else (2 if range_left <= travel + EPS else 3)
	var at: float = offset + travel
	var pierce: int = int(shot.pierce)
	if pierce >= 0 and contacts.size() > pierce:
		at = offset + float(contacts[pierce].t) * travel
		priority = 1
	return {"shot": shot, "remaining": remaining, "offset": offset, "travel": travel,
		"contacts": contacts, "at": at, "priority": priority}


func _natural_end(shot: Dictionary, reason: String, events: Array[Dictionary], time: float) -> void:
	if not bool(shot.active):
		return
	# Mark terminal before dispatching effects. Re-entry cannot duplicate an explosion.
	_finish(shot, reason, events, time)
	_event(events, "flight_ended", shot, time, {"reason": reason})
	if _effect(shot, "explode_on_flight_end", "flight_ended"):
		var payload: Dictionary = Recipes.secondary_packet(shot.snapshot, str(shot.skill_id))
		if payload.is_empty():
			return
		_event(events, "explosion", shot, time, {"pos": shot.pos, "effect_id": "explosion:%d" % int(shot.id),
			"radius": float(shot.snapshot.get("explosion_recipe", Recipes.TORNADO.explosion).radius), "payload": payload, "snapshot": shot.snapshot,
			"color": Color("ffb576"), "reason": reason})


func cancel_all(shots: Array[Dictionary], reason: String = "run_reset") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for shot: Dictionary in shots:
		_finish(shot, reason, events, 0.0)
	shots.clear()
	return events


func _effect(shot: Dictionary, id: String, event: String) -> bool:
	if not Recipes.EFFECTS.has(id) or Recipes.EFFECTS[id].event != event:
		return false
	if not shot.snapshot.get("effects", []).has(id) or shot.fired.has(id):
		return false
	shot.fired[id] = true
	return true


func _event(events: Array[Dictionary], type: String, shot: Dictionary, time: float, extra: Dictionary = {}) -> void:
	_sequence += 1
	var event: Dictionary = {"type": type, "time": time, "sequence": _sequence,
		"projectile_id": shot.id, "parent_id": shot.parent_id, "root_id": shot.root_id,
		"cast_id": shot.cast_id, "generation": shot.generation, "role": shot.role,
		"phase": shot.state, "age": shot.age, "pos": shot.pos}
	event.merge(extra, true)
	events.append(event)


func _finish(shot: Dictionary, reason: String, events: Array[Dictionary], time: float) -> void:
	if not bool(shot.active):
		return
	shot.active = false
	shot.end_reason = reason
	_event(events, "terminated", shot, time, {"reason": reason})


func _contacts(shot: Dictionary, start: Vector2, end: Vector2, targets: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var candidates: Array[int] = []
	if _index_active:
		candidates = _target_index.query_sweep(start, end, float(shot.radius))
	else:
		candidates.assign(range(targets.size()))
	if _in_advance:
		last_contact_queries += 1
		last_indexed_queries += 1 if _index_active else 0
		last_candidate_visits += candidates.size()
		last_full_scan_visits += targets.size()
	for target_index: int in candidates:
		var target: Dictionary = targets[target_index]
		var id: int = int(target.id)
		if float(target.get("health", 1.0)) <= 0.0 or float(target.get("spawn", 0.0)) > 0.0 or shot.hit_ledger.has("%s:%d" % [shot.state, id]):
			continue
		var t: float = _segment_circle(start, end, target.pos, float(shot.radius) + float(target.get("radius", 0.0)))
		if t >= 0.0:
			result.append({"id": id, "t": t})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.t), float(b.t)):
			return float(a.t) < float(b.t)
		return int(a.id) < int(b.id))
	return result


static func _segment_circle(start: Vector2, end: Vector2, center: Vector2, radius: float) -> float:
	var offset: Vector2 = start - center
	if offset.length_squared() <= radius * radius:
		return 0.0
	var delta: Vector2 = end - start
	var a: float = delta.length_squared()
	if a <= EPS:
		return -1.0
	var b: float = 2.0 * offset.dot(delta)
	var c: float = offset.length_squared() - radius * radius
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var t: float = (-b - sqrt(discriminant)) / (2.0 * a)
	return t if t >= 0.0 and t <= 1.0 else -1.0
