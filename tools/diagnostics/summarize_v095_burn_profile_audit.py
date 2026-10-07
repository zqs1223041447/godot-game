#!/usr/bin/env python3
"""Derive attribution from accepted, exact-observation diagnostic data only."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "docs/qa/v095-profile"
assert json.loads((QA / "verification.json").read_text())["accepted"]
clean = json.loads((QA / "clean_completed.json").read_text())
instrumented = json.loads((QA / "instrumented_completed.json").read_text())


def aggregate(samples):
    result = {}
    for sample in samples:
        for key, value in sample["meter"].items():
            if key == "eligible_monster_numeric_zero_calls":
                continue
            target = result.setdefault(key, {"us": 0, "calls": 0})
            target["us"] += value["us"]
            target["calls"] += value["calls"]
    return result


def profile_bounds(meter, clean_us, instrumented_us):
    body = sum(meter["defense_profile_body/" + p]["us"] for p in ["other", "planning", "settlement"])
    envelope = sum(meter["defense_profile_call_envelope/" + p]["us"] for p in ["other", "planning", "settlement"])
    incoming = sum(meter["incoming_burn/" + p]["us"] for p in ["other", "planning", "settlement"])
    return {
        "profile_body_us": body,
        "profile_call_envelope_us": envelope,
        "incoming_burn_us": incoming,
        "narrow_window_percent_of_instrumented_tick": 100 * body / instrumented_us,
        "wide_window_percent_of_instrumented_tick": 100 * envelope / instrumented_us,
        "narrow_window_percent_of_instrumented_incoming": 100 * body / incoming if incoming else 0,
        "wide_window_percent_of_instrumented_incoming": 100 * envelope / incoming if incoming else 0,
        "zero_to_wide_window_budget_percent_of_clean_tick": [0, 100 * envelope / clean_us],
        "guaranteed_production_savings_lower_bound_us": 0,
        "guaranteed_production_savings_upper_bound_established": False,
    }


rows = []
for cr, ir in zip(clean["rows"], instrumented["rows"], strict=True):
    assert cr["mode"] == ir["mode"]
    meter = aggregate(ir["samples"])
    clean_total = sum(s["cpu_us"] for s in cr["samples"])
    instrumented_total = sum(s["cpu_us"] for s in ir["samples"])
    frame_rows = []
    for cs, ins in zip(cr["samples"], ir["samples"], strict=True):
        frame_rows.append({
            "frame": ins["frame"], "clean_tick_us": cs["cpu_us"], "instrumented_tick_us": ins["cpu_us"],
            "events": {k: ins[k] for k in ["hits", "kills", "enemies", "projectiles", "burns", "particles", "pickups", "feedback", "pending_feedback"]},
            "meter": ins["meter"], "bounds": profile_bounds(ins["meter"], cs["cpu_us"], ins["cpu_us"]),
        })
    rows.append({"mode": ir["mode"], "frames": ir["frames"], "clean_tick_total_us": clean_total, "instrumented_tick_total_us": instrumented_total, "phase_totals": meter, "bounds": profile_bounds(meter, clean_total, instrumented_total), "per_frame": frame_rows})

result = {
    "scope": "One accepted same-state short diagnostic, not a candidate optimization or production benchmark claim.",
    "timing": "Time.get_ticks_usec elapsed windows, including scheduling and instrumentation; nested phases are inclusive and not additive.",
    "bounds": "Narrow/wide are two observed timing boundaries, not confidence limits or guaranteed production-savings bounds. True savings lower bound is zero; no guaranteed upper bound follows from one perturbed process pair. Wide/clean is a deliberately generous attribution budget only.",
    "rows": rows,
}
(QA / "attribution.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps([{k: v for k, v in r.items() if k != "per_frame"} for r in rows], indent=2))
