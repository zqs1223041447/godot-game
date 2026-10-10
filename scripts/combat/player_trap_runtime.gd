class_name PlayerTrapRuntime
extends RefCounted
## Bounded ephemeral carriers only. The caller checks current live enemies,
## birth protection and terrain, then consumes one trap before settling its hit.
## Never pre-plan all triggers: an earlier hit may kill a later trap's target.
## No nodes, damage, RNG, persistent saves, or projectile capacity live here.
const Rules = preload("res://scripts/combat/ambush_support_rules.gd")
const Program = preload("res://scripts/combat/support_program.gd")
const Supports = preload("res://scripts/combat/support_registry.gd")
const Base = preload("res://scripts/combat/damage_base_compiler.gd")
const Critical = preload("res://scripts/combat/critical_strike_runtime.gd")
const Data = preload("res://scripts/game_data.gd")
const MAX_TRAPS: int = 3
const MAX_DATA_VALUES: int = 32768
const MAX_DATA_DEPTH: int = 16
const MAX_ID: int = 9223372036854775807
var _entries: Array[Dictionary] = []
var _next_id: int = 1
var _clock: float = 0.0


## Read-only preflight before mana/cooldown/critical draws/cast IDs are spent.
## Expired storage does not consume a slot, but is only pruned after acceptance.
func can_place(at: Variant, position: Variant, compiled: Variant) -> Dictionary:
	var reason: String = _time_error(at)
	if reason.is_empty() and (not position is Vector2 or not position.is_finite()):
		reason = "Trap position must be a finite Vector2"
	if reason.is_empty(): reason = _compiled_error(compiled)
	if not reason.is_empty(): return _result(reason)
	var time: float = float(at)
	var armed_at: float = time + float(Rules.POLICY.arming_seconds)
	var expires_at: float = time + float(Rules.POLICY.lifetime_seconds)
	if not is_finite(expires_at) or armed_at <= time or expires_at <= armed_at:
		return _result("Trap deadlines are not representable at this timestamp")
	if _next_id >= MAX_ID: return _result("Trap identity capacity reached")
	var count: int = 0
	for entry: Dictionary in _entries:
		if time < float(entry.expires_at): count += 1
	if count >= MAX_TRAPS: return {"ok": false, "error": "Trap capacity reached", "error_code": "capacity"}
	return _result()


## All input validation precedes mutation and deep-copying. The critical-frozen
## snapshot must belong to this exact compiled cast. Old traps retain their own
## placement snapshots when equipment, supports or talents change afterwards.
func place(at: Variant, position: Variant, compiled: Variant, frozen_snapshot: Variant, cast_id: Variant) -> Dictionary:
	var admitted: Dictionary = can_place(at, position, compiled)
	if not admitted.ok: return {"ok": false, "error": admitted.error, "error_code": admitted.get("error_code", "invalid"), "id": 0}
	var reason: String = ""
	if typeof(cast_id) != TYPE_INT or cast_id <= 0:
		reason = "Trap cast identity must be a positive integer"
	if reason.is_empty(): reason = _frozen_error(frozen_snapshot, compiled.snapshot)
	if not reason.is_empty(): return {"ok": false, "error": reason, "id": 0}
	var time: float = float(at)
	var id: int = _next_id
	var skill_id: String = compiled.skill_id
	var entry: Dictionary = {"id": id, "position": position, "skill_id": skill_id,
		"cast_id": cast_id, "radius": float(compiled.recipe.get("radius", 0.0)),
		"slow": float(compiled.recipe.get("slow", Data.SKILLS.nova.slow_duration)) if skill_id == "nova" else 0.0, "color": Data.SKILLS[skill_id].color,
		"packet": compiled.packets.get("direct", {}).duplicate(true), "snapshot": frozen_snapshot.duplicate(true),
		"placed_at": time, "armed_at": time + float(Rules.POLICY.arming_seconds),
		"expires_at": time + float(Rules.POLICY.lifetime_seconds),
		"trigger_radius": float(Rules.POLICY.trigger_radius)}
	if skill_id == "chain":
		entry.erase("radius"); entry.erase("packet")
		entry.recipe = compiled.recipe.duplicate(true)
		entry.bounces = compiled.packets.bounces.duplicate(true)
	_expire(time)
	_entries.append(entry)
	_clock = time
	_next_id += 1
	return {"ok": true, "error": "", "id": id}


## Half-open lifetime: expiry equality wins over arming/triggering. Only small
## detached candidate rows are copied each tick; snapshots stay in owned storage.
func ready(at: Variant) -> Dictionary:
	var reason: String = _time_error(at)
	if not reason.is_empty(): return {"ok": false, "error": reason, "ready": []}
	var time: float = float(at)
	_expire(time)
	_clock = time
	var rows: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if time >= float(entry.armed_at):
			rows.append({"id": entry.id, "position": entry.position, "trigger_radius": entry.trigger_radius})
	return {"ok": true, "error": "", "ready": rows}


## Ownership transfers on successful consumption. Removing before returning
## guarantees exactly-once hits without a second frozen-state copy.
func take(id: Variant, at: Variant) -> Dictionary:
	var reason: String = _time_error(at)
	if reason.is_empty() and (typeof(id) != TYPE_INT or id <= 0):
		reason = "Trap identity must be a positive integer"
	if not reason.is_empty(): return {"ok": false, "error": reason, "entry": {}}
	var time: float = float(at)
	for index: int in _entries.size():
		var entry: Dictionary = _entries[index]
		if int(entry.id) != id: continue
		if time >= float(entry.expires_at):
			return {"ok": false, "error": "Trap has expired", "entry": {}}
		if time < float(entry.armed_at):
			return {"ok": false, "error": "Trap is not armed", "entry": {}}
		_entries.remove_at(index)
		_expire(time)
		_clock = time
		return {"ok": true, "error": "", "entry": entry}
	return {"ok": false, "error": "Trap identity is not active", "entry": {}}


## Presentation reads never advance the simulation clock or mutate storage.
func statuses(at: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _time_error(at).is_empty(): return result
	var time: float = float(at)
	for entry: Dictionary in _entries:
		if time >= float(entry.expires_at): continue
		result.append({"id": entry.id, "position": entry.position, "skill_id": entry.skill_id,
			"armed": time >= float(entry.armed_at), "remaining_seconds": float(entry.expires_at) - time,
			"arming_remaining_seconds": maxf(0.0, float(entry.armed_at) - time)})
	return result


func reset() -> void:
	_entries.clear()
	_next_id = 1
	_clock = 0.0


func is_empty() -> bool:
	return _entries.is_empty()


## Retained storage, including expired entries awaiting successful advancement.
func active_count() -> int:
	return _entries.size()


func _expire(at: float) -> void:
	for index: int in range(_entries.size() - 1, -1, -1):
		if at >= float(_entries[index].expires_at): _entries.remove_at(index)


func _time_error(at: Variant) -> String:
	if not Program.number(at) or float(at) < 0.0: return "Trap time must be finite and nonnegative"
	if float(at) < _clock: return "Trap time must not move backwards"
	return ""


static func _compiled_error(compiled: Variant) -> String:
	if not compiled is Dictionary or not _bounded_data(compiled): return "Trap cast must be bounded pure data"
	if typeof(compiled.get("ok")) != TYPE_BOOL or not compiled.ok or compiled.get("error") != "":
		return "Trap cast must be compiled successfully"
	var skill_id: Variant = compiled.get("skill_id")
	if typeof(skill_id) != TYPE_STRING or skill_id not in Rules.SKILLS: return "Unsupported trap skill"
	var reason: String = Rules.profile_error(compiled.get("trap_profile"))
	if not reason.is_empty(): return reason
	var links: Variant = compiled.get("support_ids")
	if not Program.strings(links) or links.size() > 5 or links.count("ambush") != 1:
		return "Trap cast must select Ambush exactly once"
	reason = Supports.compatibility_reason(skill_id, links, Supports.GROUP_MAX_SUPPORTS)
	if not reason.is_empty(): return reason
	if not Program.number(compiled.get("mana")) or float(compiled.mana) < 0.0 or not Program.number(compiled.get("cooldown")) or float(compiled.cooldown) <= 0.0:
		return "Trap cast cost and cooldown must be valid"
	if typeof(compiled.get("initial_count")) != TYPE_INT or compiled.initial_count != 0:
		return "Trap casts cannot emit initial projectiles"
	var recipe: Variant = compiled.get("recipe")
	var packets: Variant = compiled.get("packets")
	if skill_id == "chain":
		reason = _chain_payload_error(recipe, packets, links)
		if not reason.is_empty(): return reason
	else:
		if not recipe is Dictionary or not Program.number(recipe.get("radius")) or float(recipe.radius) <= 0.0 or float(recipe.radius) > 500.0:
			return "Trap blast radius is invalid"
		if not packets is Dictionary or packets.size() != 1 or not packets.has("direct"):
			return "Trap cast must retain one direct packet"
		reason = Base.packet_error(packets.direct)
		if not reason.is_empty(): return reason
		if packets.direct.skill_id != skill_id or packets.direct.role != "direct" or packets.direct.tags != ["hit", "spell", "area"]:
			return "Trap packet must retain its original spell area hit identity"
	if skill_id == "nova":
		var program: Dictionary = Supports.compile_programs(skill_id, links, Supports.GROUP_MAX_SUPPORTS)
		var expected: float = float(Data.SKILLS.nova.slow_duration) * float(program.recipe_factors.get("slow_duration_multiplier", 1.0))
		var slow: Variant = recipe.get("slow", Data.SKILLS.nova.slow_duration)
		if not Program.number(slow) or float(slow) != expected: return "Trap nova slow duration is invalid"
	var snapshot: Variant = compiled.get("snapshot")
	if not snapshot is Dictionary or snapshot.get("compiled_skill_id") != skill_id or snapshot.get("compiled_packets") != packets or snapshot.has("critical_roll"):
		return "Trap snapshot must belong to its unrolled compiled cast"
	var modifiers: Variant = snapshot.get("modifiers")
	if not modifiers is Array: return "Trap snapshot modifiers are invalid"
	var ambush_count: int = 0
	for modifier: Variant in modifiers:
		if not modifier is Dictionary or modifier.get("mode") not in ["increased", "more"] or not Program.number(modifier.get("value")):
			return "Trap snapshot contains an invalid damage modifier"
		for field: String in ["all_tags", "skills", "damage_types"]:
			if not Program.strings(modifier.get(field, [])): return "Trap modifier scopes are invalid"
		for tag: String in modifier.get("all_tags", []):
			if tag not in Base.TAGS: return "Trap modifier contains an unsupported damage tag"
		for type: String in modifier.get("damage_types", []):
			if type not in Base.Damage.TYPES: return "Trap modifier contains an unsupported damage type"
		for skill: String in modifier.get("skills", []):
			if skill != "basic" and not Data.SKILLS.has(skill): return "Trap modifier contains an unsupported skill"
		if modifier.get("id") == "support:ambush":
			if modifier != Program.primary_modifier("ambush", skill_id, -0.15): return "Trap hit tradeoff is invalid"
			ambush_count += 1
	if ambush_count != 1: return "Trap hit tradeoff must occur exactly once"
	return Critical.snapshot_error(snapshot)


## One bounded, original chain recipe; supports do not alter the trigger radius.
static func _chain_payload_error(recipe: Variant, packets: Variant, links: Array) -> String:
	if not recipe is Dictionary or recipe.size() != 3 or not recipe.has_all(["hit","first_range","followup_range"]): return "Trap chain recipe is invalid"
	var program: Dictionary = Supports.compile_programs("chain", links, Supports.GROUP_MAX_SUPPORTS)
	if not program.error.is_empty(): return program.error
	var hit: Dictionary = Data.SKILLS.chain.hit_recipe.duplicate(true)
	hit.bounce_count += int(program.recipe_factors.get("chain_extra_targets", 0))
	if recipe.hit != hit or not Program.number(recipe.first_range) or recipe.first_range != Data.SKILLS.chain.targeting_recipe.first_range:
		return "Trap chain hit recipe is invalid"
	var followup: float = float(Data.SKILLS.chain.targeting_recipe.followup_range) * float(program.recipe_factors.get("chain_followup_range_multiplier", 1.0))
	if not Program.number(recipe.followup_range) or recipe.followup_range != followup: return "Trap chain followup range is invalid"
	if not packets is Dictionary or packets.size() != 1 or not packets.get("bounces") is Array or packets.bounces.size() != int(hit.bounce_count):
		return "Trap chain packets are invalid"
	for packet: Variant in packets.bounces:
		var reason: String = Base.packet_error(packet)
		if not reason.is_empty(): return reason
		if packet.skill_id != "chain" or packet.role != "bounce" or packet.tags != ["hit","spell","chain"]: return "Trap chain packet identity is invalid"
	return ""


static func _frozen_error(snapshot: Variant, compiled: Dictionary) -> String:
	if not snapshot is Dictionary or not _bounded_data(snapshot): return "Frozen trap snapshot must be bounded pure data"
	if snapshot.size() != compiled.size() + int(snapshot.has("critical_roll")):
		return "Frozen trap snapshot does not match its compiled cast"
	for key: Variant in compiled:
		if not snapshot.has(key) or snapshot[key] != compiled[key]: return "Frozen trap snapshot does not match its compiled cast"
	var profile: Dictionary = compiled.get("critical", {}).get("primary", {})
	if profile.is_empty() or float(profile.chance) == 0.0:
		return "Unexpected critical roll on a zero-chance trap" if snapshot.has("critical_roll") else ""
	var roll: Variant = snapshot.get("critical_roll")
	if not roll is Dictionary or roll.size() != 3 or not roll.has_all(["critical", "multiplier", "chance"]) or typeof(roll.critical) != TYPE_BOOL:
		return "Trap needs its placement-time critical result"
	if not Program.number(roll.chance) or roll.chance != profile.chance or not Program.number(roll.multiplier) or roll.multiplier != (profile.multiplier if roll.critical else 1.0):
		return "Frozen trap critical result is invalid"
	if float(profile.chance) == 1.0 and not roll.critical: return "Guaranteed critical trap must retain its critical result"
	return ""


## Reject object references, cycles, excessive nesting and nonfinite numbers
## before any duplicate(true). This bounds accepted storage and validation work.
static func _bounded_data(value: Variant) -> bool:
	return _data_size(value, 0, MAX_DATA_VALUES) >= 0


static func _data_size(value: Variant, depth: int, budget: int) -> int:
	if depth > MAX_DATA_DEPTH or budget < 1: return -1
	var used: int = 1
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT: return used
		TYPE_FLOAT: return used if is_finite(value) else -1
		TYPE_STRING, TYPE_STRING_NAME: return used if str(value).length() <= 4096 else -1
		TYPE_VECTOR2: return used if value.is_finite() else -1
		TYPE_COLOR: return used if is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a) else -1
		TYPE_ARRAY, TYPE_DICTIONARY:
			if value.size() > budget - 1: return -1
			for key: Variant in value:
				if value is Dictionary and (typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).length() > 128): return -1
				var size: int = _data_size(value[key] if value is Dictionary else key, depth + 1, budget - used)
				if size < 0: return -1
				used += size
			return used
	return -1


static func _result(error: String = "") -> Dictionary:
	return {"ok": error.is_empty(), "error": error}
