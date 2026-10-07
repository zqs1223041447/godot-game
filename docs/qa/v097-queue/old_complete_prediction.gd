extends RefCounted
## Pure adapter of d2d188ab's complete current-status prediction scan.
## Original block is preserved in original-main-prediction.txt; compare exactly
## with the documented extraction in run_checks.py. No queue calls are used.
const Defense = preload("res://scripts/mechanics/defense_rules.gd")


static func scan(statuses: Array, targets: Dictionary, to_time: float) -> Dictionary:
	var states:Array[Dictionary]=[]
	var death_times:Dictionary={}
	var cut:float=to_time
	var predictions:Dictionary={}
	for status:Dictionary in statuses:
		if status.target_kind!="monster":continue
		var target:Dictionary=targets.get(int(status.target_id),{})
		if target.is_empty() or float(target.health)<=0.0:
			continue
		assert(float(status.last_time)<=to_time,"Monster burn timeline cannot move backwards")
		states.append(status)
		var expiry:float=float(status.provenance.get("ember_expiry",float(status.last_time)+float(status.remaining)))
		var end:float=minf(to_time,expiry)
		if end<=float(status.last_time):continue
		var rate:Dictionary=Defense.incoming_burn(float(status.raw_dps),target.get("resistances",{}).get("fire",0.0),0.0,1.0,"monster")
		assert(rate.ok,"Validated burn defense")
		if float(rate.damage_total)<=0.0:continue
		var death_at:float=float(status.last_time)+(float(target.get("shield",0.0))+float(target.health))/float(rate.damage_total)
		if death_at<=float(status.last_time):
			# A positive lifetime smaller than one clock ULP still needs the
			# next representable instant; never spin at a zero-width boundary.
			var bits:=PackedByteArray();bits.resize(8);bits.encode_double(0,float(status.last_time))
			bits.encode_u64(0,bits.decode_u64(0)+1);death_at=bits.decode_double(0)
		predictions[int(status.target_id)]={"death_at":death_at,"expiry":expiry,"damage_rate":rate.damage_total}
		if death_at<=end:
			death_times[int(status.target_id)]=death_at
			cut=minf(cut,death_at)
	return {"states":states,"death_times":death_times,"cut":cut,"predictions":predictions}


static func from_rows(rows: Array, to_time: float) -> Dictionary:
	var statuses: Array = []
	var targets: Dictionary = {}
	for row: Dictionary in rows:
		statuses.append({"target_kind": "monster", "target_id": row.target_id,
			"last_time": row.last_time, "remaining": float(row.expires_at) - float(row.last_time),
			"raw_dps": row.raw_dps, "provenance": {"ember_expiry": row.expires_at}})
		targets[row.target_id] = {"health": row.health, "shield": row.shield, "resistances": {"fire": row.fire_resistance}}
	return scan(statuses, targets, to_time)
