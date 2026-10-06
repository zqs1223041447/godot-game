extends RefCounted
## Adapt one already-ordered projectile event batch to a causal burn clock.
## The original approximate comparator is non-transitive. Adjacent raw offsets
## may form a tie chain whose endpoints are not approximately equal. Preserve
## event order; never compare cumulative elapsed time or silently accept a real
## backward jump. Each call starts a fresh batch with no retained state.
static func offsets(events: Variant) -> Dictionary:
	if not events is Array:return {"ok":false,"reason":"Event batch must be an array","offsets":[]}
	var result:Array[float]=[]
	var previous:float=-1.0
	var clock:float=-1.0
	for event:Variant in events:
		if not event is Dictionary or not event.has("time") or not (event.time is int or event.time is float):
			return {"ok":false,"reason":"Event offset must be a number","offsets":[]}
		var raw:float=float(event.time)
		if not is_finite(raw) or raw<0.0:return {"ok":false,"reason":"Event offset must be finite and nonnegative","offsets":[]}
		if raw<clock and not is_equal_approx(raw,previous):
			return {"ok":false,"reason":"Event order reverses time outside an adjacent raw-offset tie chain","offsets":[]}
		clock=maxf(clock,raw)
		result.append(clock)
		previous=raw
	return {"ok":true,"reason":"","offsets":result}
