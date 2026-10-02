class_name EncounterAdmission
extends RefCounted
## Transactional boundary around the existing identity/lineage factory.
## No dictionary escapes to the simulation until every transform has succeeded.
const Compiler = preload("res://scripts/encounters/encounter_compiler.gd")

static func create_root(runtime: RefCounted, profile: Variant, template_id: String, wave: int,
		position: Vector2, context: String, rarity: String, mechanisms: Array, rewards: bool) -> Dictionary:
	var reason: String = Compiler.profile_error(profile)
	if not reason.is_empty(): return {"ok":false,"error":reason}
	var before: Dictionary = _snapshot(runtime)
	var canonical: Dictionary = runtime.create_root(template_id,wave,position,context,rarity,mechanisms,rewards)
	if canonical.is_empty():
		_restore(runtime,before)
		return {"ok":false,"error":"挑战怪物生成失败"}
	var result: Dictionary = Compiler.apply_to_enemy(canonical,profile)
	if not result.ok: _restore(runtime,before)
	return result

static func drain(runtime: RefCounted, profile: Variant, available: int, bounds: Rect2) -> Dictionary:
	var reason: String = Compiler.profile_error(profile)
	if not reason.is_empty(): return {"ok":false,"error":reason}
	if available <= 0 or runtime.queue.is_empty():
		return {"ok":true,"error":"","enemies":[]}
	var before: Dictionary = _snapshot(runtime)
	var canonical: Array[Dictionary] = runtime.drain(available,bounds)
	# A factory rejection may consume a queued request without returning an enemy.
	var expected: int = mini(maxi(0,available),before.queue.size())
	if canonical.size()!=expected:
		_restore(runtime,before)
		return {"ok":false,"error":"挑战子怪生成失败，队列已保留"}
	var result: Array[Dictionary] = []
	for enemy: Dictionary in canonical:
		var applied: Dictionary = Compiler.apply_to_enemy(enemy,profile)
		if not applied.ok:
			_restore(runtime,before)
			return {"ok":false,"error":str(applied.error)}
		result.append(applied.enemy)
	return {"ok":true,"error":"","enemies":result}

static func _snapshot(runtime: RefCounted) -> Dictionary:
	return {"queue":runtime.queue.duplicate(true),"roots":runtime.roots.duplicate(true),
		"trace":runtime.trace.duplicate(true),"next_id":runtime.next_id}

static func _restore(runtime: RefCounted, before: Dictionary) -> void:
	runtime.queue.assign(before.queue)
	runtime.roots = before.roots
	runtime.trace.assign(before.trace)
	# These identities were never admitted or published to consumers. Existing
	# visible IDs and reset's monotonic policy are unaffected by failed admission.
	runtime.next_id = before.next_id
