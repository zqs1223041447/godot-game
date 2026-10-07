class_name TelegraphedAreaRuntime
extends RefCounted
## Bounded pure-data scheduler. No damage settlement, drawing, signals, or RNG.
## Callers supply a complete frame-start source snapshot, then consume copied events.

const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Defense = preload("res://scripts/mechanics/defense_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const BossProfiles=preload("res://scripts/monsters/map_boss_profiles.gd")
const MAX_ACTIVE: int = Profiles.MAX_ACTIVE
const TIME_EPSILON: float = 0.000000001

var _states: Dictionary = {}
var _next_attack_id: int = 1


func start(enemy: Variant, target_center: Vector2, overrides: Variant = {}, visual_pattern:Variant="") -> Dictionary:
	if not enemy is Dictionary or not _valid_id(enemy.get("id")) or not _can_attack(enemy):
		return _failure("Source must be alive and outside birth protection")
	if not visual_pattern is String:return _failure("Visual pattern must be a known string")
	if enemy.get("map_boss_attack_id","")=="ginkgo_shelter_slam" and visual_pattern!="ginkgo_shelter_slam":
		return _failure("Ginkgo requires its authoritative two-stage pattern")
	var ember_burn:bool=enemy.get("template_id","")=="ember_guard" and not enemy.has("map_boss_attack_id")
	var storm_shock:bool=enemy.get("template_id","")=="storm_skitter" and not enemy.has("map_boss_attack_id")
	var frost_chill:bool=enemy.get("template_id","")=="frost_guard" and not enemy.has("map_boss_attack_id")
	var chaos_guard:bool=enemy.get("template_id","")=="chaos_guard" and not enemy.has("map_boss_attack_id")
	if ember_burn and visual_pattern.is_empty():visual_pattern="ember_burn"
	if storm_shock and visual_pattern.is_empty():visual_pattern="storm_shock"
	if chaos_guard and visual_pattern.is_empty():visual_pattern="chaos_guard"
	if visual_pattern=="ember_burn":
		if not ember_burn:return _failure("Burn pattern must match the ember guard")
	elif visual_pattern=="storm_shock":
		if not storm_shock:return _failure("Shock pattern must match the storm skitter")
	elif visual_pattern=="chaos_guard":
		if not chaos_guard:return _failure("Chaos pattern must match the chaos guard")
	elif not visual_pattern.is_empty() and (not BossProfiles.enemy_reason(enemy,visual_pattern).is_empty() or enemy.get("map_boss_attack_id")!=visual_pattern):return _failure("Visual pattern must match the authoritative map boss")
	var source_id: int = int(enemy.id)
	if _states.has(source_id):
		return _failure("Source already has an attack in progress")
	if _states.size() >= MAX_ACTIVE:
		return _failure("Attack capacity reached")
	if not target_center.is_finite():
		return _failure("Target center must be finite")
	var checked: Dictionary = Profiles.resolve(overrides)
	if not checked.ok:
		return checked
	if visual_pattern in ["sunwell_echo","ginkgo_shelter_slam"]:
		var authored:Dictionary=BossProfiles.definition(visual_pattern).profile
		for field:String in ["radius","windup_seconds","damage_multiplier"]:
			if float(checked.profile[field])!=float(authored[field]):
				return _failure("Ginkgo geometry, warning and per-stage budget must match the map authority" if visual_pattern=="ginkgo_shelter_slam" else "Echo geometry, warning and per-pulse budget must match the map authority")
	if visual_pattern=="ginkgo_shelter_slam":
		var policy:Dictionary=Monsters.telegraph_policy(enemy)
		if policy.is_empty() or checked.profile.recovery_seconds!=policy.profile.recovery_seconds:
			return _failure("Ginkgo recovery must match the current attack-speed policy")
	if not _nonnegative_number(enemy.get("damage")):
		return _failure("Contact damage must be finite and nonnegative")
	var weights: Variant = enemy.get("contact_weights", {"physical": 1.0})
	if not weights is Dictionary or weights.size() > Damage.TYPES.size():
		return _failure("Contact weights must be a bounded object")
	var validated: Dictionary = Defense.validate_components(weights)
	if not validated.ok or not is_equal_approx(float(validated.get("total", 0.0)), 1.0):
		return _failure("Contact weights must be valid damage types summing to one")
	# Use the existing contact-component authority only after validating its inputs.
	var components: Dictionary = Monsters.contact_components(enemy)
	for type: String in components:
		components[type] = float(components[type]) * float(checked.profile.damage_multiplier)
	validated = Defense.validate_components(components)
	if not validated.ok:
		return _failure("Scaled contact damage is invalid or overflowed")
	var burn_policy:Dictionary=Monsters.Burn.ENEMY_POLICY.duplicate(true) if ember_burn else {}
	if not burn_policy.is_empty():validated.components.fire=float(validated.components.get("fire",0.0))*float(burn_policy.upfront_fire_multiplier)
	var attack: Dictionary = {
		"source_id": source_id, "attack_id": _next_attack_id, "phase": "windup", "elapsed": 0.0,
		"center": target_center, "profile": checked.profile,
		"packet": Damage.packet(validated.components, ["attack", "area", "hit"], Profiles.PROFILE_ID),
	}
	if not burn_policy.is_empty():attack.burn_policy=burn_policy
	if storm_shock:attack.shock_policy=Monsters.Shock.ENEMY_POLICY.duplicate(true)
	if frost_chill:attack.chill_policy=Monsters.Chill.ENEMY_POLICY.duplicate(true)
	if not visual_pattern.is_empty():attack.visual_pattern=visual_pattern
	if visual_pattern in ["sunwell_echo","ginkgo_shelter_slam"]:
		var echo:Dictionary=BossProfiles.definition(visual_pattern)
		attack.pulse_count=int(echo.pulse_count);attack.pulse_interval=float(echo.pulse_interval);attack.pulses_emitted=0
		if visual_pattern=="ginkgo_shelter_slam":
			attack.second_pulse=echo.second_pulse
			attack.profile_id=echo.profile_id;attack.balance_version=echo.balance_version
			attack.packet.skill_id=echo.profile_id
	_next_attack_id += 1
	_states[source_id] = attack
	return {"ok": true, "reason": "", "attack": state_for(source_id)}


func advance(delta: float, live_enemies: Variant, with_timing: bool = false, paused_prefixes: Dictionary = {}) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	# Prefixes pause only each source's local action clock, never its liveness.
	# Keys name members of the complete snapshot, including dead/protected sources.
	# A new pause batch is transactional, including validation of its source universe.
	# Empty batches retain the original fail-closed cancellation contract.
	if not paused_prefixes.is_empty() and (paused_prefixes.size() > MAX_ACTIVE or not is_finite(delta) or delta < 0.0):
		return events
	# Reject a partial/ambiguous source universe rather than guessing who survived.
	if not live_enemies is Array or live_enemies.size() > MAX_ACTIVE:
		if paused_prefixes.is_empty(): reset()
		return events
	var live: Dictionary = {}
	for enemy: Variant in live_enemies:
		if not enemy is Dictionary or not _valid_id(enemy.get("id")) or live.has(enemy.id):
			if paused_prefixes.is_empty(): reset()
			return events
		live[enemy.id] = _can_attack(enemy)
	for source_id: Variant in paused_prefixes:
		var prefix: Variant = paused_prefixes[source_id]
		if not _valid_id(source_id) or not live.has(source_id) or not _nonnegative_number(prefix) or float(prefix) > delta:
			return events
	var pending: Array[Dictionary] = []
	for source_id: int in _states.keys():
		# Cancellation also runs on zero, negative, or nonfinite delta.
		if not bool(live.get(source_id, false)):
			_states.erase(source_id)
			continue
		if not is_finite(delta) or delta <= 0.0:
			continue
		var paused_prefix: float = float(paused_prefixes.get(source_id, 0.0))
		var active_delta: float = delta
		if paused_prefix > 0.0:
			active_delta = delta - paused_prefix
			if active_delta <= 0.0:
				continue
		var first_pending: int = pending.size()
		var attack: Dictionary = _states[source_id]
		if attack.get("visual_pattern","") in ["sunwell_echo","ginkgo_shelter_slam"]:
			if paused_prefix > 0.0:
				_advance_echo(attack,active_delta,pending)
				_offset_pending(pending, first_pending, paused_prefix)
			else:
				_advance_echo(attack,delta,pending)
			continue
		var windup: float = float(attack.profile.windup_seconds)
		var duration: float = windup + float(attack.profile.recovery_seconds)
		var previous: float = float(attack.elapsed)
		# Cap arithmetic, not the caller's simulated time; even a huge delta finishes.
		if paused_prefix > 0.0:
			attack.elapsed = minf(duration, previous + minf(active_delta, duration))
		else:
			attack.elapsed = minf(duration, previous + minf(delta, duration))
		if attack.phase == "windup" and float(attack.elapsed) + TIME_EPSILON >= windup:
			attack.phase = "recovery"
			pending.append({"at": maxf(0.0, windup - previous), "event": {
				"type": "circle_attack", "shape": "circle", "source_id": source_id,
				"attack_id": attack.attack_id, "center": attack.center, "radius": attack.profile.radius,
				"attack_age": windup, "profile_id": Profiles.PROFILE_ID,
				"schema_version": Profiles.SCHEMA_VERSION, "balance_version": Profiles.BALANCE_VERSION,
				"profile": attack.profile.duplicate(true), "packet": attack.packet.duplicate(true),
			}})
			if attack.has("burn_policy"):pending.back().event.burn_policy=attack.burn_policy.duplicate(true)
			if attack.has("shock_policy"):pending.back().event.shock_policy=attack.shock_policy.duplicate(true)
			if attack.has("chill_policy"):pending.back().event.chill_policy=attack.chill_policy.duplicate(true)
			if with_timing or attack.has("burn_policy") or attack.has("shock_policy") or attack.has("chill_policy"):pending.back().event.step_time=maxf(0.0,windup-previous)
			if attack.has("visual_pattern"):pending.back().event.visual_pattern=attack.visual_pattern
		if paused_prefix > 0.0:
			_offset_pending(pending, first_pending, paused_prefix)
		if float(attack.elapsed) + TIME_EPSILON >= duration:
			_states.erase(source_id)
	# Stable chronological order within this call; equal deadlines use source identity.
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.at) != float(b.at):
			return float(a.at) < float(b.at)
		return int(a.event.source_id) < int(b.event.source_id))
	for item: Dictionary in pending:
		events.append(item.event)
	return events


func _offset_pending(pending: Array[Dictionary], first: int, prefix: float) -> void:
	# Convert resumed local deadlines back to this frame's clock before sorting.
	for index: int in range(first, pending.size()):
		pending[index].at = float(pending[index].at) + prefix
		if pending[index].event.has("step_time"):
			pending[index].event.step_time = float(pending[index].event.step_time) + prefix


func cancel(source_id: int) -> bool:
	return _states.erase(source_id)


func reset() -> void:
	_states.clear()
	# Like MonsterRuntime identities, attack identities never restart on reset.


func has_burning_actions()->bool:
	for value:Dictionary in _states.values():
		if value.has("burn_policy"):return true
	return false


func has_timed_sequence_actions()->bool:
	for value:Dictionary in _states.values():
		if value.get("visual_pattern","") in ["sunwell_echo","ginkgo_shelter_slam"]:return true
	return false


func active_count() -> int:
	return _states.size()


func state_for(source_id: int) -> Dictionary:
	var result:Dictionary=_states.get(source_id, {}).duplicate(true)
	if result.get("visual_pattern","")=="sunwell_echo":
		# Presentation sees the current full windup, or recovery after that
		# windup. The internal total clock and frozen center never restart.
		var index:int=mini(int(result.pulses_emitted),int(result.pulse_count)-1)
		result.pulse_index=index
		result.elapsed=maxf(0.0,float(result.elapsed)-index*float(result.pulse_interval))
	elif result.get("visual_pattern","")=="ginkgo_shelter_slam":
		var index:int=mini(int(result.pulses_emitted),int(result.pulse_count)-1)
		result.pulse_index=index
		result.shape="circle" if index==0 else "annulus"
		result.inner_radius=0.0 if index==0 else float(result.second_pulse.inner_radius)
		if index==1:
			result.elapsed=maxf(0.0,float(result.elapsed)-float(result.profile.windup_seconds))
			result.profile.radius=result.second_pulse.radius
			result.profile.windup_seconds=result.second_pulse.windup_seconds
	return result


func _advance_echo(attack:Dictionary,delta:float,pending:Array[Dictionary])->void:
	var windup:float=attack.profile.windup_seconds
	var interval:float=attack.pulse_interval
	var count:int=attack.pulse_count
	var duration:float=windup+(count-1)*interval+float(attack.profile.recovery_seconds)
	var previous:float=attack.elapsed
	attack.elapsed=minf(duration,previous+minf(delta,duration))
	while int(attack.pulses_emitted)<count:
		var index:int=attack.pulses_emitted
		var deadline:float=windup+index*interval
		if float(attack.elapsed)+TIME_EPSILON<deadline:break
		pending.append({"at":maxf(0.0,deadline-previous),"event":{
			"type":"circle_attack","shape":"circle","source_id":attack.source_id,
			"attack_id":attack.attack_id,"center":attack.center,"radius":attack.profile.radius,
			"attack_age":deadline,"profile_id":Profiles.PROFILE_ID,"schema_version":Profiles.SCHEMA_VERSION,
			"balance_version":Profiles.BALANCE_VERSION,"profile":attack.profile.duplicate(true),
			"packet":attack.packet.duplicate(true),"visual_pattern":"sunwell_echo",
			"pulse_index":index,"pulse_count":count,"step_time":maxf(0.0,deadline-previous)}})
		if attack.get("visual_pattern","")=="ginkgo_shelter_slam":
			var event:Dictionary=pending.back().event
			event.visual_pattern=attack.visual_pattern
			event.profile_id=attack.profile_id;event.balance_version=attack.balance_version
			event.inner_radius=0.0
			if index==1:
				event.type="annulus_attack";event.shape=attack.second_pulse.shape
				event.inner_radius=attack.second_pulse.inner_radius;event.radius=attack.second_pulse.radius
				event.profile.radius=attack.second_pulse.radius
				event.profile.windup_seconds=attack.second_pulse.windup_seconds
		attack.pulses_emitted=index+1
	attack.phase="recovery" if int(attack.pulses_emitted)==count else "windup"
	if float(attack.elapsed)+TIME_EPSILON>=duration:_states.erase(int(attack.source_id))


static func overlaps(event: Dictionary, position: Vector2, target_radius: float) -> bool:
	if event.get("shape")=="annulus":
		return _annulus_overlaps(event,position,target_radius)
	# One shared geometric rule for main, reference examples and boundary tests.
	var center: Variant = event.get("center")
	var radius: Variant = event.get("radius")
	if event.get("shape") != "circle" or not center is Vector2 or not center.is_finite() or not position.is_finite():
		return false
	if not _nonnegative_number(radius) or not is_finite(target_radius) or target_radius < 0.0:
		return false
	var reach: float = float(radius) + target_radius
	var squared: float = reach * reach
	return is_finite(squared) and center.distance_squared_to(position) <= squared


static func _annulus_overlaps(event:Dictionary,position:Vector2,target_radius:float)->bool:
	var center:Variant=event.get("center")
	var outer:Variant=event.get("radius")
	var inner:Variant=event.get("inner_radius")
	if not center is Vector2 or not center.is_finite() or not position.is_finite():return false
	if not _nonnegative_number(outer) or not _nonnegative_number(inner) or float(inner)<=0.0 or float(inner)>=float(outer):return false
	if not is_finite(target_radius) or target_radius<0.0:return false
	# Scalar subtraction avoids Vector2's float32 squared-distance overflow.
	var dx:float=float(position.x)-float(center.x)
	var dy:float=float(position.y)-float(center.y)
	var squared:float=dx*dx+dy*dy
	var reach:float=float(outer)+target_radius
	if is_finite(squared) and is_finite(reach):
		var distance:float=sqrt(squared)
		return distance<=reach and distance+target_radius>=float(inner)
	# Normalize before subtraction and addition for finite, extreme inputs.
	# Never let overflow turn an outside target into an inf <= inf hit.
	var scale:float=maxf(maxf(absf(float(center.x)),absf(float(center.y))),maxf(absf(float(position.x)),absf(float(position.y))))
	scale=maxf(scale,maxf(float(outer),target_radius))
	dx=float(position.x)/scale-float(center.x)/scale
	dy=float(position.y)/scale-float(center.y)/scale
	var largest:float=maxf(absf(dx),absf(dy))
	var distance:float=0.0 if largest==0.0 else largest*sqrt((dx/largest)*(dx/largest)+(dy/largest)*(dy/largest))
	return distance<=float(outer)/scale+target_radius/scale and distance+target_radius/scale>=float(inner)/scale


static func _valid_id(value: Variant) -> bool:
	return value is int and int(value) > 0


static func _nonnegative_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _can_attack(enemy: Dictionary) -> bool:
	return (_nonnegative_number(enemy.get("health")) and float(enemy.health) > 0.0
		and _nonnegative_number(enemy.get("spawn")) and float(enemy.spawn) == 0.0
		and enemy.get("death_processed", false) is bool and not bool(enemy.get("death_processed", false)))


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
