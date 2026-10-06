extends RefCounted
## Genuine released native49 equipment, talents and inventory, followed by real
## normal transactions. No fabricated gear, currency, points or unlock writes.
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Maps = preload("res://scripts/world/map_compiler.gd")
const NATIVE49 := "res://docs/qa/v082-source/fixtures/witch-refunded.json"
const MAP_ID := "ginkgo_arcade"

static func prepare(game, path: String, tier: int = 1, start_run: bool = false) -> Dictionary:
	if tier < 1 or tier > 3: return {"ok": false, "reason": "Fixture tier must be I, II or III"}
	var bytes := FileAccess.get_file_as_bytes(NATIVE49)
	var source := Rules.decode_v49(JSON.parse_string(bytes.get_string_from_utf8()))
	if source.is_empty(): return {"ok": false, "reason": "Genuine native49 fixture is invalid"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"ok": false, "reason": "Cannot write isolated fixture"}
	file.store_buffer(bytes)
	file.close()
	if not game.load_build(path): return {"ok": false, "reason": game.last_error}
	for prior: int in range(1, tier):
		var profile: Dictionary = Maps.compile_normal(MAP_ID, prior, [], []).profile
		var opened: Dictionary = game.normal_start_map(profile, game.revision(), path)
		if not opened.ok: return opened
		var completed: Dictionary = game.normal_complete_map(opened.run_id, game.revision(), path)
		if not completed.ok: return completed
		var claimed: Dictionary = game.normal_claim_rewards(game.revision(), path)
		if not claimed.ok: return claimed
	var profile: Dictionary = Maps.compile_normal(MAP_ID, tier, [], []).profile
	if start_run: return game.normal_start_map(profile, game.revision(), path)
	return {"ok": true, "reason": "", "profile": profile, "revision": game.revision()}
