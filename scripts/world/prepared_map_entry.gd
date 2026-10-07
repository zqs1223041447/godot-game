extends RefCounted
## Internal, one-use owner of detached map geometry across asynchronous setup.
## Main validates the actual geometry/routes/roster again; this is not a trusted
## "validated" flag or a persistent map/save object.
var _phase := "preparing"
var _context: PackedByteArray
var _geometry: RefCounted
var _landmarks: Dictionary = {}
var _bounds := Rect2()
var _release := Callable()

func _init(context: PackedByteArray = PackedByteArray()) -> void:
	_context = context.duplicate()

func attach(geometry: RefCounted, release: Callable) -> bool:
	if _phase != "preparing" or _geometry != null or geometry == null or not release.is_valid():
		return false
	_geometry = geometry
	_release = release
	return true

func ready(landmarks: Dictionary, bounds: Rect2) -> bool:
	if _phase != "preparing" or _geometry == null:
		return false
	_landmarks = landmarks.duplicate(true)
	_bounds = bounds
	_phase = "ready"
	return true

func phase() -> String: return _phase
func geometry_ref() -> RefCounted: return _geometry
func landmarks() -> Dictionary: return _landmarks.duplicate(true)
func bounds() -> Rect2: return _bounds
func matches_context(context: PackedByteArray) -> bool: return context == _context

func begin_use(context: PackedByteArray) -> String:
	if _phase != "ready": return "Prepared map is not ready or has already been consumed"
	if not matches_context(context):
		cancel()
		return "Map draft or live state changed during preparation"
	_phase = "in_use"
	return ""

func cancel() -> void:
	# Once Main begins the synchronous save/commit, UI signals cannot release
	# its geometry halfway through. Main alone finishes or aborts that use.
	if _phase not in ["preparing", "ready"]: return
	finish_use(false)

func finish_use(committed: bool) -> void:
	if _phase in ["transferred", "cancelled"]: return
	if committed:
		assert(_phase == "in_use")
		_phase = "transferred"
	else:
		_phase = "cancelled"
		if _release.is_valid(): _release.call()
	_release = Callable()
	_geometry = null
	_landmarks.clear()
	_context.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _release.is_valid():
		_release.call()
