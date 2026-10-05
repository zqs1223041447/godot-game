class_name EmberProliferationRules
extends RefCounted
## A bounded, one-hop transfer of an existing player's burn. No hit, random
## roll, defense, reward, or lifetime extension is performed by this selector.
const POLICY: Dictionary = {"enabled": true, "radius": 120.0, "max_targets": 8,
	"max_hops": 1, "preserves_expiry": true}


static func select_targets(origin: Variant, source_id: Variant, candidates: Variant,
		visible: Callable = Callable()) -> Dictionary:
	if not origin is Vector2 or not origin.is_finite() or typeof(source_id) != TYPE_INT or source_id <= 0 or not candidates is Array:
		return {"ok": false, "reason": "Invalid ember transfer inputs", "target_ids": []}
	var seen: Dictionary = {}
	var ranked: Array[Dictionary] = []
	for value: Variant in candidates:
		if not value is Dictionary or typeof(value.get("id")) != TYPE_INT or int(value.id) <= 0 or seen.has(value.id) \
				or not value.get("pos") is Vector2 or not value.pos.is_finite() \
				or not _number(value.get("health")) or not _number(value.get("spawn", 0.0)):
			return {"ok": false, "reason": "Invalid or duplicate ember target", "target_ids": []}
		seen[value.id] = true
		if int(value.id) == source_id or float(value.health) <= 0.0 or float(value.get("spawn", 0.0)) > 0.0: continue
		var distance: float = origin.distance_squared_to(value.pos)
		if distance > float(POLICY.radius) * float(POLICY.radius): continue
		if visible.is_valid() and not visible.call(origin, value.pos): continue
		ranked.append({"id": int(value.id), "distance": distance})
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.id) < int(right.id) if float(left.distance) == float(right.distance) else float(left.distance) < float(right.distance))
	var ids: Array[int] = []
	for entry: Dictionary in ranked:
		if ids.size() >= int(POLICY.max_targets): break
		ids.append(int(entry.id))
	return {"ok": true, "reason": "", "target_ids": ids}


static func transfer(status: Variant, at: Variant) -> Dictionary:
	if not status is Dictionary or not _number(at) or float(at) < 0.0:
		return {"ok": false, "reason": "Invalid ember status or time", "burn": {}}
	var provenance: Variant = status.get("provenance", {})
	if not provenance is Dictionary: return {"ok": false, "reason": "Invalid ember provenance", "burn": {}}
	if provenance.has("ember_generation") != provenance.has("ember_expiry"):
		return {"ok": false, "reason": "Incomplete ember lineage", "burn": {}}
	if not provenance.has("ember_generation"): return {"ok": true, "reason": "not_ember", "burn": {}}
	if typeof(provenance.ember_generation) != TYPE_INT or provenance.ember_generation not in [0, 1] \
			or not _number(provenance.get("ember_expiry")) or float(provenance.ember_expiry) <= 0.0 or not _number(status.get("raw_dps")) or float(status.raw_dps) <= 0.0:
		return {"ok": false, "reason": "Invalid ember lineage", "burn": {}}
	var remaining: float = float(provenance.ember_expiry) - float(at)
	if int(provenance.ember_generation) != 0 or remaining <= 0.0:
		return {"ok": true, "reason": "spent_or_expired", "burn": {}}
	var inherited: Dictionary = provenance.duplicate(true)
	inherited["ember_generation"] = 1
	return {"ok": true, "reason": "", "burn": {"raw_dps": float(status.raw_dps),
		"duration": remaining, "provenance": inherited}}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
