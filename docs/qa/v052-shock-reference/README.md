# v0.52 Shock offline reference verification

The offline catalog and HTML document the production Shock policies and compiler,
runtime, telegraph, trading and migration outputs. Export reports game version
0.52.0 and canonical schema 31. No gameplay, model, UI, artwork source, font,
stylesheet, browser script, project version or Git state was changed by this work.

## Commands and results

Executed from `/workspace/scratch/a51485f153de/v052-shock-mechanism`:

1. `/usr/local/bin/godot --headless --path /workspace/scratch/a51485f153de/v052-shock-mechanism --script res://tools/export_reference.gd` — exit 0, no engine/script errors
2. `python3 tools/build_reference.py` — exit 0
3. `python3 tools/build_reference.py --check` — exit 0
4. `python3 tests/shock_reference_test.py` — exit 0

The single Godot export used fresh XDG data/config/cache directories below
`/tmp/godot-m1-v052-reference-mmy5meyz`. No editor, import pass, GUI or historical
test suite ran. All 187 recorded inputs were unchanged during that first run.

Review then clarified that the chain example is the first and last preview hit
sum, not one hit or the total damage of a cast. The parent authorized this caption
correction and a Python-only rebuild. Commands 2–4 were repeated, all exit 0;
there was no second Godot export. Initial logs are retained, and the final logs
have a `-caption` suffix. Final HTML size is 9,967,433 bytes.

`run-metadata.json` records exact commands, exits, durations, XDG paths, source
stability and final output SHA256 values. `input-sha256.json` records first-run
input hashes. The metadata separately records the final builder/test hashes and
the frozen schema30 reward-oracle hash used by the focused check.

## Focused coverage

- Player policy: 2 seconds, 15% subsequent hit damage taken, primary hit ×0.8 and mana ×1.2
- Explicit support admission for bolt/nova/chain only, with real compiled previews and rejection evidence for other skills
- Ordered runtime/settlement demonstration: applying hit 100, subsequent equivalent hit 115, separate burn damage 100; equal refresh to 12.5 seconds and exact-expiry inactivity
- Enemy policy: storm_skitter telegraph only, 1 second/15%; upfront damage ×1.4, warning 0.7 seconds, radius 65, baseline recovery 1.6 seconds
- Normal purchase quote 4 calibration shards; independent free test supply
- Strict schema30-to31 example changes only version, grants no items, and preserves frozen old reward vocabulary and 27 reward ordinals against the released oracle
- Rendered numeric evidence, Shock cross-links, source text, unchanged embedded CSS/JS, and byte-identical source icon

This is a focused documentation/structure pass, not an additional gameplay test
count or full historical-suite result. The DOT example uses the production burn
settlement function, whose interface has no Shock multiplier.

Icon SHA256:
`40bd93320cc088e1eeb38413f63731af92ac7904b2866609d4c12f871ef9a662`

## Files for parent staging

- `tools/export_reference.gd`
- `tools/build_reference.py`
- `tests/shock_reference_test.py`
- `docs/reference/catalog.json`
- `docs/reference/index.html`
- `docs/reference/originals/shock.png`
- This `docs/qa/v052-shock-reference/` directory
