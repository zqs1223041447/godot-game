extends "res://scripts/main.gd"
## Diagnostic subclass only. Never instantiated by a scene or production file.
## A whole-batch sufficient bound selects before super dispatches any event.
const BatchGuard = preload("res://tools/diagnostics/burn_batch_guard.gd")
const DeadlineShadow = preload("res://tools/diagnostics/burn_deadline_shadow.gd")
var shadow_batches: Array[Dictionary] = []
var _shadow_active: bool = false
var _shadow_clock: float = 0.0
var _shadow_target: int = 0
var _shadow_targets: Dictionary = {}
var _shadow_waiting_feedback: Dictionary = {}
var _shadow_deadlines = DeadlineShadow.new()
var _shadow_advances: int = 0


func _settle_projectile_events(events: Array[Dictionary], original_delta: float = 0.0) -> bool:
	if events.is_empty() or not burn_runtime.has_ember_states():
		return super._settle_projectile_events(events, original_delta)
	if _ember_advancing or _ember_flushing or _ember_defer_deaths or not _ember_deaths.is_empty():
		_shadow_record({"eligible":false,"reason":"pending_or_reentrant_death_boundary","events":events.size()})
		return super._settle_projectile_events(events, original_delta)
	# Nothing has been settled here. Ineligible batches retain the original
	# dispatcher, clocks, full advancement, deaths, feedback and rewards.
	var start: float = _burn_step_start if _burn_step_active else elapsed
	var plan: Dictionary = BatchGuard.plan(events, enemies, burn_runtime.statuses(), start, elapsed, original_delta)
	if not shock_runtime.is_empty(): plan = {"eligible":false,"reason":"active_shock_requires_original_path"}
	if not plan.get("eligible",false):
		_shadow_record({"eligible":false,"reason":plan.get("reason","guard_rejected"),"events":events.size()})
		return super._settle_projectile_events(events, original_delta)
	_shadow_targets.clear(); _shadow_waiting_feedback.clear()
	for enemy: Dictionary in enemies: _shadow_targets[int(enemy.id)] = enemy
	var rows: Array = []
	for status: Dictionary in burn_runtime.statuses():
		if status.target_kind != "monster": continue
		var id: int = int(status.target_id)
		rows.append(_shadow_row(status,_shadow_targets[id]))
		if not _shadow_has_feedback(id): _shadow_waiting_feedback[id] = true
	var configured: Dictionary = _shadow_deadlines.configure(rows)
	if not configured.ok:
		_shadow_record({"eligible":false,"reason":configured.reason,"events":events.size()})
		return super._settle_projectile_events(events, original_delta)
	_shadow_clock = maxf(start,burn_runtime.latest_monster_time())
	_shadow_advances = 0; _shadow_target = 0; _shadow_active = true
	var accepted: bool = super._settle_projectile_events(events, original_delta)
	# The original dispatcher calls our flush override before returning.
	assert(not _shadow_active, "Diagnostic lazy state must close before dispatcher returns")
	_shadow_record({"eligible":true,"reason":"preflight_nonlethal_zero_shield","events":events.size(),"target_advances":_shadow_advances})
	return accepted


func _apply_damage_packet(enemy: Dictionary, packet: Dictionary, snapshot: Dictionary, color: Color,
		slow: float = 0.0, provenance: Dictionary = {}) -> void:
	if not _shadow_active:
		super._apply_damage_packet(enemy,packet,snapshot,color,slow,provenance); return
	_shadow_target = int(enemy.id)
	super._apply_damage_packet(enemy,packet,snapshot,color,slow,provenance)
	# These are diagnostics, not a rollback route. A violated preflight aborts
	# the experiment; it never undoes already emitted gameplay side effects.
	assert(float(enemy.health)>0.0 and float(enemy.get("shield",0.0))==0.0,"Nonlethal zero-shield proof must hold after the actual hit")
	var status: Dictionary = burn_runtime.status_for("monster",int(enemy.id))
	if not status.is_empty():
		var updated: Dictionary = _shadow_deadlines.upsert(_shadow_row(status,enemy))
		assert(updated.ok,"Accepted batch has representable updated deadline")
		if not _shadow_has_feedback(int(enemy.id)): _shadow_waiting_feedback[int(enemy.id)] = true
	_shadow_target = 0


func _ember_event_time(at: float, event: Dictionary) -> float:
	if not _shadow_active: return super._ember_event_time(at,event)
	if not _ember_projectile_clock.is_empty() and event.get("sequence",-1)==_ember_projectile_clock.sequence and event.get("time",-1.0)==_ember_projectile_clock.raw:
		at = _burn_event_time(float(_ember_projectile_clock.offset))
	var latest: float = maxf(at,_shadow_clock)
	if latest>at:
		assert(_burn_step_active and event.has("time") and latest<=elapsed and is_equal_approx(float(event.time),latest-_burn_step_start),"Original relative tie must justify a backwards raw timestamp")
	return latest


func _advance_proliferating_burns(to_time: float) -> void:
	if not _shadow_active:
		super._advance_proliferating_burns(to_time); return
	assert(to_time>=_shadow_clock and to_time<=elapsed,"Batch causal clock remains ordered")
	var first: Dictionary = _shadow_deadlines.peek()
	assert(first.is_empty() or float(first.deadline)>to_time,"Due death/expiry must have failed the side-effect-free guard")
	var ids: Array = []
	if _shadow_target>0: ids.append(_shadow_target)
	# First positive burn receipts retain original ID order. Once registered,
	# no repeated full pending-bucket enumeration or empty reservation is needed.
	for id: int in _shadow_waiting_feedback:
		if not ids.has(id): ids.append(id)
	ids.sort()
	_shadow_materialize(ids,to_time)
	_shadow_clock = to_time


func _flush_monster_spawns() -> void:
	if _shadow_active:
		var ids: Array = []
		for status: Dictionary in burn_runtime.statuses():
			if status.target_kind=="monster": ids.append(int(status.target_id))
		ids.sort()
		_shadow_materialize(ids,_shadow_clock)
		_shadow_active=false; _shadow_target=0
		_shadow_deadlines.clear(); _shadow_targets.clear(); _shadow_waiting_feedback.clear()
	super._flush_monster_spawns()


func _shadow_materialize(ids: Array, at: float) -> void:
	for id: int in ids:
		var status: Dictionary = burn_runtime.status_for("monster",id)
		if status.is_empty(): continue
		var advanced: Dictionary = burn_runtime.advance_target("monster",id,at)
		_assert_burn_result(advanced)
		_settle_burn_segments(advanced.segments,_shadow_targets)
		_shadow_advances += int(not advanced.segments.is_empty())
		var target: Dictionary = _shadow_targets[id]
		assert(float(target.health)>0.0,"Preflight excludes every burn death in the lazy batch")
		if _shadow_has_feedback(id): _shadow_waiting_feedback.erase(id)
		status=burn_runtime.status_for("monster",id)
		assert(not status.is_empty(),"Preflight excludes expiry inside the lazy batch")
		var updated: Dictionary = _shadow_deadlines.upsert(_shadow_row(status,target))
		assert(updated.ok,"Materialized deadline remains representable")


func _shadow_has_feedback(id: int) -> bool:
	return feedback_runtime._pending.has(feedback_runtime._key("monster",id,"burn"))


static func _shadow_row(status: Dictionary, enemy: Dictionary) -> Dictionary:
	return {"target_id":int(status.target_id),"last_time":float(status.last_time),
		"raw_dps":float(status.raw_dps),"expires_at":float(status.provenance.get("ember_expiry",float(status.last_time)+float(status.remaining))),
		"shield":float(enemy.get("shield",0.0)),"health":float(enemy.health),
		"fire_resistance":enemy.get("resistances",{}).get("fire",0.0)}


func _shadow_record(value: Dictionary) -> void:
	shadow_batches.append(value)
	if shadow_batches.size()>32: shadow_batches.pop_front()
