extends RefCounted
## One shared lawful source route for source, actual-Main and F8 checks.
## prepare preserves owned items and creates an explicitly level23 fixture.
## Every paid node and selected mastery is then purchased through model commands.
const NORMAL_ROUTE: Array[String] = ["54447", "57226", "21678", "32210", "8948", "38176", "49651", "5296", "19501",
	"5972", "36412", "22090", "40609", "8833", "4367", "44184", "61804", "13559", "31462", "11924",
	"32431", "36121", "57362", "55647", "56716"]
const MASTERIES := {"fire":{"id":"34927","effect":65020}, "cold":{"id":"60170","effect":4116}, "lightning":{"id":"58816","effect":53046}}
const CLASS_ID := 3
const LEVEL := 23
const BUDGET := 27


static func prepare(game, path: String, selected: Array = ["fire", "cold", "lightning"]) -> Dictionary:
	var candidate: Dictionary = game.snapshot()
	candidate.talents.class_id = CLASS_ID
	candidate.progress = {"level":LEVEL,"xp":0}
	candidate.talents.allocated = [NORMAL_ROUTE[0]]
	candidate.talents.masteries = {}
	candidate.talents.normal_points = BUDGET
	candidate.revision += 1
	var result: Dictionary = game._commit(candidate, path)
	if not result.ok: return result
	for id: String in NORMAL_ROUTE.slice(1):
		result = game.allocate_passive(id, 0, game.revision(), path)
		if not result.ok: return result
	return select(game, path, selected)


## Empty choices still retain both notable6% penetration grants on NORMAL_ROUTE.
static func select(game, path: String, selected: Array) -> Dictionary:
	for type: Variant in selected:
		if not type is String or not MASTERIES.has(type): return {"ok":false,"reason":"Unknown fixture mastery"}
	for type: String in MASTERIES:
		var id: String = MASTERIES[type].id
		if game.snapshot().talents.allocated.has(id) and not selected.has(type):
			var refunded: Dictionary = game.refund_passive(id, game.revision(), path)
			if not refunded.ok: return refunded
	for type: String in MASTERIES:
		var choice: Dictionary = MASTERIES[type]
		if selected.has(type) and not game.snapshot().talents.allocated.has(choice.id):
			var allocated: Dictionary = game.allocate_passive(choice.id, choice.effect, game.revision(), path)
			if not allocated.ok: return allocated
	return {"ok":true,"reason":"","revision":game.revision()}
