#!/usr/bin/env python3
"""Generate transparent diagnostic copies; never edit production scripts."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "docs/qa/v095-profile"
QA.mkdir(parents=True, exist_ok=True)
METER_PATH = "res://docs/qa/v095-profile/meter.gd"
MAIN_PATH = "res://docs/qa/v095-profile/main_profiled.gd"
DEFENSE_PATH = "res://docs/qa/v095-profile/defense_profiled.gd"


def replace_once(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new, 1)


meter = '''extends RefCounted
## Side-channel data only. No production result or simulation state is stored.
static var enabled: bool = false
static var phase: int = 0
static var incoming_depth: int = 0
static var totals: Array[int] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
static var calls: Array[int] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
static var eligible_calls: Array[int] = [0,0,0]
static func add(metric: int, duration: int, location: int = 0) -> void:
\tvar index: int = metric * 3 + location
\ttotals[index] += duration
\tcalls[index] += 1
static func reset() -> void:
\tassert(incoming_depth == 0 and phase == 0)
\ttotals.fill(0); calls.fill(0); eligible_calls.fill(0)
static func snapshot() -> Dictionary:
\tvar result: Dictionary = {}
\tvar metrics: Array[String] = ["incoming_burn", "defense_profile_body", "defense_profile_call_envelope", "advance_total", "settlement_total", "trace_build"]
\tvar phases: Array[String] = ["other", "planning", "settlement"]
\tfor metric: int in range(metrics.size()):
\t\tfor location: int in range(3):
\t\t\tvar index: int = metric * 3 + location
\t\t\tresult[metrics[metric] + "/" + phases[location]] = {"us": totals[index], "calls": calls[index]}
\tresult["eligible_monster_numeric_zero_calls"] = eligible_calls.duplicate()
\treturn result
'''
(QA / "meter.gd").write_text(meter)

defense_source = (ROOT / "scripts/mechanics/defense_rules.gd").read_text()
defense = re.sub(r"^class_name .*\n", "", defense_source, flags=re.M)
defense = replace_once(defense, "extends RefCounted\n", f'extends RefCounted\nconst V095Meter = preload("{METER_PATH}")\n')
for name, args, metric, condition in [
    ("defense_profile", "stats, actor, stage", 1, "not V095Meter.enabled or V095Meter.incoming_depth == 0"),
    ("incoming_burn", "raw_amount, fire_resistance, shield, health, actor, mana, ratio, max_fire_bonus", 0, "not V095Meter.enabled"),
]:
    declaration = next(line for line in defense.splitlines() if line.startswith("static func " + name + "("))
    body_declaration = declaration.replace("func " + name, "func _v095_" + name + "_body")
    wrapper = declaration + "\n"
    wrapper += f"\tif {condition}: return _v095_{name}_body({args})\n"
    if name == "incoming_burn":
        wrapper += "\tV095Meter.incoming_depth += 1\n"
    wrapper += "\tvar v095_began: int = Time.get_ticks_usec()\n"
    wrapper += f"\tvar v095_result: Dictionary = _v095_{name}_body({args})\n"
    wrapper += "\tvar v095_duration: int = Time.get_ticks_usec() - v095_began\n"
    wrapper += f"\tV095Meter.add({metric}, v095_duration, V095Meter.phase)\n"
    if name == "incoming_burn":
        wrapper += "\tV095Meter.incoming_depth -= 1\n"
        wrapper += '\tif actor == "monster" and _finite_number(ratio) and float(ratio) == 0.0 and _finite_number(max_fire_bonus) and float(max_fire_bonus) == 0.0:\n'
        wrapper += "\t\tV095Meter.eligible_calls[V095Meter.phase] += 1\n"
    wrapper += "\treturn v095_result\n\n\n" + body_declaration
    defense = replace_once(defense, declaration, wrapper)
profile_line = '\tvar profile:Dictionary=defense_profile({"fire_resistance":fire_resistance},actor)'
defense = replace_once(defense, profile_line, '\tvar v095_profile_began: int = Time.get_ticks_usec() if V095Meter.enabled else 0\n' + profile_line + '\n\tif V095Meter.enabled: V095Meter.add(2, Time.get_ticks_usec() - v095_profile_began, V095Meter.phase)')
(QA / "defense_profiled.gd").write_text(defense)

main_source = (ROOT / "scripts/main.gd").read_text()
main = re.sub(r"^class_name .*\n", "", main_source, flags=re.M)
main = replace_once(main, 'const Defense = preload("res://scripts/mechanics/defense_rules.gd")', f'const Defense = preload("{DEFENSE_PATH}")\nconst V095Meter = preload("{METER_PATH}")')
for name, args, metric in [
    ("_advance_proliferating_burns", "to_time", 3),
    ("_settle_burn_segments", "segments, targets, death_states, exact_deaths", 4),
]:
    declaration = next(line for line in main.splitlines() if line.startswith("func " + name + "("))
    body_declaration = declaration.replace("func " + name, "func _v095" + name + "_body")
    wrapper = declaration + "\n"
    wrapper += f"\tif not V095Meter.enabled:\n\t\t_v095{name}_body({args})\n\t\treturn\n"
    wrapper += "\tvar v095_previous_phase: int = V095Meter.phase\n"
    wrapper += f"\tV095Meter.phase = {1 if metric == 3 else 2}\n"
    wrapper += "\tvar v095_began: int = Time.get_ticks_usec()\n"
    wrapper += f"\t_v095{name}_body({args})\n"
    wrapper += "\tvar v095_duration: int = Time.get_ticks_usec() - v095_began\n"
    wrapper += f"\tV095Meter.add({metric}, v095_duration)\n"
    wrapper += "\tV095Meter.phase = v095_previous_phase\n\n\n" + body_declaration
    main = replace_once(main, declaration, wrapper)
trace_start = '\t\tvar record:Dictionary=segment.duplicate(true);record.settlement=settlement;record.effective_raw_amount=raw'
trace_end = '\t\tif burn_trace.size()>32:burn_trace.pop_front()'
main = replace_once(main, trace_start, '\t\tvar v095_trace_began: int = Time.get_ticks_usec() if V095Meter.enabled else 0\n' + trace_start)
main = replace_once(main, trace_end, trace_end + '\n\t\tif V095Meter.enabled: V095Meter.add(5, Time.get_ticks_usec() - v095_trace_began)')
(QA / "main_profiled.gd").write_text(main)

harness_source = (ROOT / "tools/diagnostics/burn_settlement_profile.gd").read_text()
harness = harness_source.replace('## Short exact-observation stress comparison; timed calls are production only.', '## v095: exact-observation clean/instrumented diagnostic, fixed 20+4 frames.')
harness = replace_once(harness, 'const ProductionMain=preload("res://scripts/main.gd")', f'const ProductionMain=preload("res://scripts/main.gd")\nconst ProfiledMain=preload("{MAIN_PATH}")\nconst V095Meter=preload("{METER_PATH}")')
harness = replace_once(harness, 'var instrumented:=false', 'var instrumented:=OS.get_environment("V095_INSTRUMENTED")=="1"')
harness = harness.replace('DENSITY_PROFILE_OUT', 'V095_PROFILE_OUT').replace('/tmp/godot-m1-v063-', '/tmp/godot-m1-v095-').replace('b93018005413444ad6f988974f4ef3ea09902c5e', 'eaf298a8cbd22c8387da28da118a15afdcd2afb5')
harness = harness.replace('not instrumented and OS.get_environment("DENSITY_CAPTURE_INVERSION")!="1"', 'not instrumented')
harness = harness.replace('for mode:String in ["no_burn","ember_deaths"]:', 'for mode:String in ["ember_deaths","no_burn"]:')
harness = harness.replace('DENSITY_MODE', 'V095_MODE')
harness = replace_once(harness, 'var arena:Node=ProductionMain.new()', 'var arena:Node=ProfiledMain.new() if instrumented else ProductionMain.new()')
harness = replace_once(harness, 'var frames:int=150 if mode=="ember_deaths" else 24', 'var frames:int=20 if mode=="ember_deaths" else 4')
harness = replace_once(harness, '\t\t\tvar began:=Time.get_ticks_usec();arena.tick(STEP);var total:int=Time.get_ticks_usec()-began', '\t\t\tV095Meter.reset();V095Meter.enabled=instrumented\n\t\t\tvar began:=Time.get_ticks_usec();arena.tick(STEP);var total:int=Time.get_ticks_usec()-began\n\t\t\tV095Meter.enabled=false\n\t\t\tvar frame_meter:Dictionary=V095Meter.snapshot()\n\t\t\tassert(V095Meter.incoming_depth==0 and V095Meter.phase==0)')
harness = replace_once(harness, '"frame":frame,"cpu_us":total,', '"frame":frame,"cpu_us":total,"meter":frame_meter,')
harness = replace_once(harness, '\t\t\tframe_observations.append(observe(arena))', '\t\t\tvar frame_observation:Dictionary=observe(arena)\n\t\t\tframe_observations.append(frame_observation)\n\t\t\tsamples.back()["observation_sha256"]=sha(var_to_bytes(frame_observation))\n\t\t\tprint("V095_FRAME ",mode," ",frame," ",total)')
harness = replace_once(harness, '\t\tvar observation:Dictionary=observe(arena)', '\t\tvar observation:Dictionary=observe(arena)\n\t\tassert(var_to_bytes(observation)==var_to_bytes(frame_observations.back()))')
harness = replace_once(harness, '\t\tassert(arena.save_build(),"Final unchanged-state save must succeed")', '\t\tassert(arena.save_build(),"Final unchanged-state save must succeed")\n\t\tvar final_bytes:PackedByteArray=var_to_bytes(observe(arena))\n\t\tf=FileAccess.open(out.trim_suffix(".json")+"-"+mode+"-final.bin",FileAccess.WRITE);f.store_buffer(final_bytes);f.close()')
harness = replace_once(harness, '"observation_bytes":binary.size()', '"observation_bytes":binary.size(),"final_observation_sha256":sha(final_bytes),"final_observation_bytes":final_bytes.size()')
harness = harness.replace('LATEST_DENSITY_PROFILE_COMPLETE', 'V095_BURN_PROFILE_AUDIT_COMPLETE')
harness = replace_once(harness, '\treturn {"enemies":', '\tvar original:Dictionary={"enemies":')
harness += '''
\toriginal["v095_latest_state"]={
\t\t"freeze":[arena.freeze_runtime._states.duplicate(true),arena.freeze_runtime._last_settlement_at],
\t\t"chill":[arena.chill_runtime._state.duplicate(true),arena.chill_runtime._last_settlement_at],
\t\t"trap":[arena.trap_runtime._entries.duplicate(true),arena.trap_runtime._next_id,arena.trap_runtime._clock,arena.trap_trace.duplicate(true)],
\t\t"telegraphs":[arena.telegraphs._states.duplicate(true),arena.telegraphs._next_attack_id,arena.telegraph_trace.duplicate(true)],
\t\t"feedback_ids":[arena.feedback_runtime._epoch,arena.feedback_runtime._next_sequence,arena.feedback_runtime._next_id,arena.feedback_runtime._next_outcome_id,arena.feedback_runtime._next_observation_id],
\t\t"observation_queues":[arena.feedback_runtime._outcomes.duplicate(true),arena.feedback_runtime._observation_pending.duplicate(true),arena.feedback_runtime._observation_visible.duplicate(true)],
\t\t"shock_internal":[arena.shock_runtime._states.duplicate(true),arena.shock_runtime._previous_intervals.duplicate(true),arena.shock_runtime._discarded_until,arena.shock_runtime._status_keys.duplicate(),arena.shock_runtime._status_order_dirty],
\t\t"leech_internal":[arena.leech_runtime._time,arena.leech_runtime._heaps.duplicate(true),arena.leech_runtime._rates.duplicate(true),arena._leech_caps.duplicate(true)],
\t\t"flask_internal":[arena.flask_runtime._charges.duplicate(true),arena.flask_runtime._active.duplicate(true),arena.flask_runtime._charge_remainders_micro.duplicate(true)],
\t\t"burn_flags":[arena._ember_advancing,arena._ember_defer_deaths,arena._ember_flushing,arena._burn_step_active,arena._burn_step_start,arena._burn_immunity_until,arena._burn_incoming_time],
\t\t"projectile_ids":[arena.projectile_runtime.next_projectile_id,arena.projectile_runtime.next_cast_id,arena.projectile_runtime._sequence,arena._projectile_targets.duplicate(true)],
\t\t"monster_next_id":arena.monster_runtime.next_id,
\t\t"player":[arena.player_pos,arena.player_facing,arena._player_evasion_entropy,arena.hurt_flash,arena.screen_shake,arena.alive,arena.wave],
\t\t"progress":[arena._progress_transaction_depth,arena._progress_revision,arena._progress_hud_dirty,arena._progress_save_dirty,arena._progress_save_requested,arena._progress_flushing,arena._progress_saving,arena.progress_hud_refresh_count,arena.progress_save_attempt_count,arena.progress_save_success_count],
\t\t"world":[arena._world_mode,arena._world_revision,arena._normal_run_id,arena._normal_completion_pending,arena.run_revision,arena._simulation_accumulator,arena._autosave_timer,arena.ordinary_admissions,arena.boss_wave_pending],
\t\t"map_queues":[arena._map_spawn_records.duplicate(true),arena._map_mechanism_config.duplicate(true),arena._map_optional_encounters.duplicate(true),arena._camp_movement.duplicate(true),arena._camp_requested.duplicate(true),arena._camp_wait_reasons.duplicate(true),arena._boss_requested],
\t}
\treturn original
'''
(ROOT / "tools/diagnostics/burn_profile_allocation_audit.gd").write_text(harness)

# Recover function bodies to prove instrumentation preserved every original line.
def recover_function(text, name, new_name, static=False):
    prefix = "static func " if static else "func "
    start = text.index(prefix + name + "(")
    body_start = text.index(prefix + new_name + "(", start)
    text = text[:start] + text[body_start:]
    return text.replace(prefix + new_name + "(", prefix + name + "(", 1)

recovered_main = main
for name in ["_advance_proliferating_burns", "_settle_burn_segments"]:
    recovered_main = recover_function(recovered_main, name, "_v095" + name + "_body")
recovered_main = recovered_main.replace(f'const Defense = preload("{DEFENSE_PATH}")\nconst V095Meter = preload("{METER_PATH}")', 'const Defense = preload("res://scripts/mechanics/defense_rules.gd")')
recovered_main = recovered_main.replace('\t\tvar v095_trace_began: int = Time.get_ticks_usec() if V095Meter.enabled else 0\n', '').replace('\n\t\tif V095Meter.enabled: V095Meter.add(5, Time.get_ticks_usec() - v095_trace_began)', '')
assert recovered_main == main_source
recovered_defense = defense
for name in ["defense_profile", "incoming_burn"]:
    recovered_defense = recover_function(recovered_defense, name, "_v095_" + name + "_body", True)
recovered_defense = 'class_name DefenseRules\n' + recovered_defense.replace(f'const V095Meter = preload("{METER_PATH}")\n', '')
recovered_defense = recovered_defense.replace('\tvar v095_profile_began: int = Time.get_ticks_usec() if V095Meter.enabled else 0\n', '').replace('\n\tif V095Meter.enabled: V095Meter.add(2, Time.get_ticks_usec() - v095_profile_began, V095Meter.phase)', '')
assert recovered_defense == defense_source
sources = ["scripts/main.gd", "scripts/mechanics/defense_rules.gd", "tools/diagnostics/burn_settlement_profile.gd"]
manifest = {"base_commit": "eaf298a8cbd22c8387da28da118a15afdcd2afb5", "original_bodies_roundtrip_exact": True, "source_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources}, "frames": {"ember_deaths": 20, "no_burn": 4}}
(QA / "generation_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
