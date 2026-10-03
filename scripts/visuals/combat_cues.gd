class_name CombatCues
extends RefCounted
## Presentation-only lifetime pool. Never reads RNG, rolls, saves, or combat state.
const MAX_CUES: int = 96
const LIFETIMES: Dictionary = {
	"cleave":0.28,"cast":0.24,"nova":0.45,"ward":0.60,"meteor":0.65,"chain":0.28,
	"dash":0.32,"impact":0.20,"hurt":0.24,"death":0.40,
	"split":0.24,"return":0.20,"explosion":0.55,
}
const PRIORITY: Dictionary = {
	"cleave":2,"cast":1,"nova":2,"ward":2,"meteor":2,"chain":2,"dash":2,
	"impact":0,"hurt":2,"death":0,"split":1,"return":1,"explosion":2,
}
var cues: Array[Dictionary] = []
var next_id: int = 1
var dropped: int = 0

func reset() -> void:
	cues.clear()
	next_id = 1
	dropped = 0

func emit_cue(kind: String, origin: Vector2, data: Dictionary = {}) -> int:
	if not LIFETIMES.has(kind) or not origin.is_finite():
		return 0
	var destination: Vector2 = data.get("destination",origin) if data.get("destination",origin) is Vector2 else origin
	var direction: Vector2 = data.get("direction",Vector2.RIGHT) if data.get("direction",Vector2.RIGHT) is Vector2 else Vector2.RIGHT
	var radius: float = float(data.get("radius",20.0)) if data.get("radius",20.0) is float or data.get("radius",20.0) is int else 20.0
	var tint: Color = data.get("color",Color("98e4d5")) if data.get("color",Color.WHITE) is Color else Color("98e4d5")
	if not is_finite(tint.r) or not is_finite(tint.g) or not is_finite(tint.b) or not is_finite(tint.a):
		return 0
	if not destination.is_finite() or not direction.is_finite() or not is_finite(radius):
		return 0
	# Whitelist scalar/value fields. Caller dictionaries and gameplay objects are never retained.
	var cue: Dictionary = {"id":next_id,"kind":kind,"origin":origin,"destination":destination,
		"direction":direction.normalized() if direction.length_squared()>0.001 else Vector2.RIGHT,
		"radius":clampf(radius,1,500),"age":0.0,"duration":float(LIFETIMES[kind]),
		"skill":str(data.get("skill","")).left(32),"shielded":data.get("shielded",false)==true,
		"target_id":int(data.get("target_id",0)) if data.get("target_id",0) is int else 0,
		"color":tint}
	if kind == "cleave":
		var angle: Variant=data.get("half_angle")
		if not (angle is float or angle is int) or not is_finite(float(angle)) or float(angle)<=0.0 or float(angle)>PI: return 0
		cue.half_angle=float(angle)
	if cues.size() >= MAX_CUES:
		var incoming: int = int(PRIORITY[kind])
		var replacement: int = -1
		for i: int in range(cues.size()):
			if int(PRIORITY[cues[i].kind]) < incoming:
				replacement = i
				break
		if replacement < 0:
			# Newest feedback wins at the same priority; decorative cues cannot evict boundaries.
			for i: int in range(cues.size()):
				if int(PRIORITY[cues[i].kind]) == incoming:
					replacement = i
					break
		if replacement < 0:
			dropped += 1
			return 0
		cues.remove_at(replacement)
		dropped += 1
	cues.append(cue)
	next_id += 1
	return int(cue.id)

func advance(delta: float) -> void:
	if delta <= 0 or not is_finite(delta):
		return
	for cue: Dictionary in cues:
		cue.age = float(cue.age)+delta
	cues = cues.filter(func(cue: Dictionary) -> bool: return float(cue.age) < float(cue.duration))
