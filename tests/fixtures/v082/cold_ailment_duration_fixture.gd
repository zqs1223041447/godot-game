extends RefCounted
## Shared lawful level4/eight-point source fixture. Existing owned items are retained.
## Every paid node is allocated through the real save-first model command.
const WITCH_ROUTE: Array[String] = ["54447", "57226", "21678", "32210", "8948", "27659", "37671", "27415", "14209"]
const SHADOW_ROUTE: Array[String] = ["44683", "38129", "11334", "15549", "20546", "21301", "37671", "27415", "14209"]
const LEVEL := 4
const BUDGET := 8
const TARGET := "14209"


static func prepare(game, path: String, allocate_target: bool = true, class_id: int = 3) -> Dictionary:
	if class_id not in [3, 6]: return {"ok":false,"reason":"Fixture supports Witch or Shadow only"}
	var route: Array[String] = WITCH_ROUTE if class_id == 3 else SHADOW_ROUTE
	var candidate: Dictionary = game.snapshot()
	candidate.talents.class_id = class_id
	candidate.progress = {"level":LEVEL,"xp":0}
	candidate.talents.allocated = [route[0]]
	candidate.talents.masteries = {}
	candidate.talents.normal_points = BUDGET
	candidate.revision += 1
	var result: Dictionary = game._commit(candidate, path)
	if not result.ok: return result
	for id: String in route.slice(1):
		if id == TARGET and not allocate_target: continue
		result = game.allocate_passive(id, 0, game.revision(), path)
		if not result.ok: return result
	return {"ok":true,"reason":"","revision":game.revision()}
