extends RefCounted
## Two bounded detours for the study and formal map on the v111 native assembly.
## The caller owns installation/readiness and adopts the same geometry later.
## Never mutate source landmarks, rebuild collision space or consume game RNG.
const StudyGeometry = preload("res://scripts/studies/modular_study_geometry.gd")
const Layout = preload("res://scripts/world/exploration_map_layout.gd")
const SOURCE_SEGMENTS := 12
const ROUTE_WIDTH := 72.0
const PLAYER_RADIUS := 15.0
const CLEARANCE_RADIUS := ROUTE_WIDTH * 0.5 + PLAYER_RADIUS
const ROCK_BEND := Vector2(1020, 1980)
const ARCH_BEND := Vector2(1500, 1920)


static func prepare(original_landmarks: Dictionary, geometry: RefCounted) -> Dictionary:
	if not geometry is StudyGeometry or not geometry.physics_ready():
		return _failure("Study route geometry is not ready")
	var snapshot: Dictionary = geometry.snapshot()
	var map_id: String = str(snapshot.get("source_map_id", ""))
	if map_id not in ["old_garden", "ruins_garden"] or snapshot.get("id") != ("modular_study" if map_id == "old_garden" else map_id) or not snapshot.get("bounds") is Rect2:
		return _failure("Study routes require the native old_garden assembly")
	var bounds: Rect2 = snapshot.bounds
	if bounds.size != Layout.MINIMUM_SIZE or not StudyGeometry._plain_metadata(original_landmarks):
		return _failure("Study routes require bounded detached old_garden landmarks")
	var source: Dictionary = Layout.layout(map_id, bounds)
	var originals: Variant = original_landmarks.get("route_segments")
	if not source.ok or not originals is Array or originals.size() != SOURCE_SEGMENTS:
		return _failure("Study routes require the twelve original segments")
	# Restrict this adapter to the exact authored route contract. Extra plain
	# segment/landmark metadata is preserved, including on the split segments.
	for index: int in range(SOURCE_SEGMENTS):
		var segment: Variant = originals[index]
		var expected: Dictionary = source.landmarks.route_segments[index]
		if not segment is Dictionary or segment.get("from") != expected.from or segment.get("to") != expected.to or segment.get("width") != ROUTE_WIDTH:
			return _failure("Study source route %d does not match old_garden" % index)
	var routes: Array[Dictionary] = []
	for index: int in range(SOURCE_SEGMENTS):
		var segment: Dictionary = originals[index]
		if index == 0 or index == 10:
			var bend := bounds.position + (ROCK_BEND if index == 0 else ARCH_BEND)
			var first: Dictionary = segment.duplicate(true)
			var second: Dictionary = segment.duplicate(true)
			first.to = bend
			second.from = bend
			routes.append_array([first, second])
		else:
			routes.append(segment.duplicate(true))
	# Every route keeps the formal half-width clearance. The four new detour
	# legs additionally clear the player's radius beyond that paint footprint.
	# Untouched segment 5 passes radius 36 but cannot promise radius 51.
	for index: int in range(routes.size()):
		var segment: Dictionary = routes[index]
		var radius := CLEARANCE_RADIUS if index in [0, 1, 11, 12] else ROUTE_WIDTH * 0.5
		if not geometry.is_clear(segment.from, radius) or not geometry.is_clear(segment.to, radius) or geometry.sweep(segment.from, segment.to, radius).hit or geometry.sweep(segment.to, segment.from, radius).hit:
			return _failure("Study route %d is blocked at radius %s" % [index, radius])
	var landmarks := original_landmarks.duplicate(true)
	landmarks.route_segments = routes
	return {"ok": true, "reason": "", "landmarks": landmarks}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "landmarks": {}}
