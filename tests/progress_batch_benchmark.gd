extends SceneTree
## Descriptive CPU benchmark, never a hardware threshold or rendering/FPS claim.
## Each measured sample is one PUBLIC nova cast or tick with 100 true root kills.
## Setup, scene construction and reset are outside timing. Real signals, HUD builds,
## atomic save writes, rewards, RNG and mechanics remain enabled in both modes.
const Fixture = preload("res://tests/fixtures/progress_batch_fixture.gd")
const SAMPLES: int = 5
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("Progress benchmark: %s; Godot %s; %s; %d logical processors; headless debug; no rendering/FPS claim" % [OS.get_name(), Engine.get_version_info().string, OS.get_processor_name(), OS.get_processor_count()])
	print("Fixture: catalog root HP/shields/XP, live build damage 100000, player invulnerability 100 seconds; 100 radial targets in nova or 100 spaced targets + one 100000-damage projectile each; no direct death-helper loop")
	for scenario: String in ["roots_cast", "mixed_tick"]:
		var reference: Dictionary = {}
		for batching: bool in [false, true]:
			var durations: Array[int] = []
			var cumulative: Dictionary = {"signals": 0, "hud_refreshes": 0, "save_attempts": 0, "save_successes": 0}
			var final: Dictionary = {}
			for sample: int in range(SAMPLES + 1):
				var arena: Node2D = Fixture.create(self, batching)
				Fixture.prepare_combat(arena, scenario)
				var start: int = Time.get_ticks_usec()
				var accepted: bool = Fixture.execute(arena, scenario)
				var duration: int = Time.get_ticks_usec() - start
				var counts: Dictionary = Fixture.counts(arena)
				if not accepted or arena.kills != 100 or arena.reward_kills != 100 or (scenario.contains("tick") and int(arena.event_counts.get("hit", 0)) != 100):
					failures += 1
					push_error("Benchmark sample did not execute 100 genuine rewarded root kills")
				if counts.save_attempts != counts.spy_attempts or counts.save_successes != counts.spy_successes or not Fixture.saved_matches(arena):
					failures += 1
					push_error("Benchmark counters/persisted bytes disagree with independent save spy")
				if sample > 0:
					durations.append(duration)
					for key: String in cumulative:
						cumulative[key] += int(counts[key])
				final = Fixture.final_snapshot(arena)
				arena.free()
				await process_frame
			durations.sort()
			var total_usec: int = 0
			for duration: int in durations:
				total_usec += duration
			var summary: Dictionary = {"scenario": scenario, "mode": "batched" if batching else "historical_per_signal", "samples": SAMPLES, "warmups": 1, "root_kills_per_sample": 100,
				"transaction_ms_mean": total_usec / float(SAMPLES) / 1000.0, "transaction_ms_p50": durations[SAMPLES / 2] / 1000.0,
				"transaction_ms_max": durations.back() / 1000.0, "total_root_kills": 100 * SAMPLES, "totals": cumulative}
			print(JSON.stringify(summary))
			if batching:
				if final != reference:
					failures += 1
					push_error("Benchmark final gameplay/model/RNG/IDs/reward/capacity/saved bytes differ: " + scenario)
				else:
					print("Exact complete state and saved-byte equivalence: " + scenario)
			else:
				reference = final
	print("Progress benchmark: %d correctness failures; wall-time is descriptive only; model save counts exclude any extra legacy backup write" % failures)
	quit(1 if failures else 0)
