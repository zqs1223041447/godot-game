extends "res://tests/exploration_main_flow_test.gd"
## Same lawful default map on both sides of the seam change. No seasonal fixture.
var seeded := false
var death_contract: Array[Dictionary] = []

func fingerprint(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()

func pause() -> void:
	super.pause()
	if not seeded:
		arena.rng.seed = 158423086
		seeded = true

func kill(enemy: Dictionary) -> void:
	var was_alive := float(enemy.health) > 0.0
	super.kill(enemy)
	if not was_alive: return
	death_contract.append({"actor_id": enemy.id, "root_id": enemy.root_id,
		"generation": enemy.generation, "template_id": enemy.template_id,
		"state_sha256": fingerprint(arena.state.snapshot()),
		"runtime_sha256": fingerprint(arena.EncounterAdmission._snapshot(arena.monster_runtime)),
		"flasks_sha256": fingerprint(arena.flask_runtime.snapshot()),
		"rng": str(arena.rng.state), "run": arena._map_run.snapshot(),
		"reward_kills": arena.reward_kills, "hint": arena.exploration_cleanup_hint()})

func finish() -> void:
	write_json("default-contract.json", {"method": "Fixed-seed lawful formal Main entry, controlled original defense deaths, completion claim and paid atomic reentry; no seasonal actors or ownership grants",
		"entries": report.entries, "full_run": report.full_run, "deaths": death_contract,
		"final_state": arena.state.snapshot(), "final_rng": str(arena.rng.state),
		"final_flasks": arena.flask_runtime.snapshot()})
	super.finish()
