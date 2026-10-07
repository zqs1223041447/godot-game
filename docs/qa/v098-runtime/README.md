# v098 Longstride focused runtime evidence

The focused compiler and actual Main checks passed. Production code was not changed by this worker. This is a controlled headless integration fixture, not natural combat, DPS, FPS, Windows, or full-release acceptance.

## Results

- Compiler: 138 passing checks in `first.log`, before the fixture helper failure. Four new support combinations, all 11 permutations, detached output/input checks, dash-only compatibility, slot consumption, re-entry rejection, and 24 representative complete cast byte comparisons against pinned d2d188a Compiler + support registry
- Main final: 265 checks, 0 failures, exit 0 in `main3.log` and `main3-result.json`
- Main first rerun: 249 checks, 0 failures, exit 0 in `main2.log`. Final Main rerun added strict equality for retained immunity, false-valued malformed profiles, global RNG rejection checks, bag-location proof for the no-op fixture return, and save-file byte preservation
- First failed run retained in `first.log` / `first-result.json`: the helper treated an already bag-owned support's lawful `no_change` return as failure. This was a test setup error, not a production failure. The helper now validates that the item is already in its bag location

No compiler rerun was needed after the Main-only helper/assertion changes. The compiler sections stayed unchanged. No further Godot runs were made after the coordinator requested the tested source be frozen.

## Actual Main coverage

A single Main instance loads the checked-in legal v094 owned-equipment fixture into isolated storage and migrates it. No fabricated gear, repeated fresh models, or shared save path is used. Dash and three supports are obtained via the existing award API, then moved through canonical owned-item transactions into group8. Formal normal-map draft and entry reach the actual exploration runtime before controlled position/resource resets.

Open-world results (requested distance equals actual displacement in clear ground):

| Support selection | Distance | Mana | Cooldown | Own protection grant |
| --- | ---: | ---: | ---: | ---: |
| None | 175 | 12 | 3 | 0.6 |
| Longstride | 280 | 14.4 | 3 | 0 |
| Longstride + Efficiency | 280 | 11.52 | 3.45 | 0 |
| Longstride + Quickcast | 280 | 20.16 | 2.4 | 0 |
| Longstride + Efficiency + Quickcast | 280 | 16.128 | 2.76 | 0 |

The test checks the real owned-group cooldown path for all four new combinations, retains existing 0.8 / 0.43 protection exactly, leaves zero at zero, and settles an immediate incoming hit after Longstride while ordinary dash blocks that hit. It checks no outgoing packets, projectile carriers, attack-admission receipts, leech, burn, or shock procs.

Malformed profiles, missing profiles, extra keys, nonfinite values, numeric type mismatch, unselected profiles, and non-dash policy use reject before position/facing, mana, cooldown, cast/projectile IDs, gameplay RNG, critical RNG, damage receipts, saved model, or file bytes change. Global RNG is also checked for malformed policy rejection. Insufficient mana, existing cooldown, HUD, death, readiness, town, and completed-map gates remain atomic.

Actual exploration wall sweeps and diagonal slides keep the player's body outside the wall. Both distances stop at x1146.98 in the selected wall case; the longer diagonal slide reaches y1431.99 versus y1357.744. Every traversed segment remains wall-clear, the recorded path terminates at the actual reached point, and the same-frame camera and dash cue use that reached point. Both casts clip to the exact body-radius world corner. Returning the supports to the bag restores the full pre-selection owned cast.

## Reuse for presentation

`owned-fixture-after-runtime.json` is the exact legal schema53 save copied from the completed final run, with no subsequent Godot execution. Group is `group_000008`, dash UID is `item_000010`, and support UIDs are `item_000011` (Longstride), `item_000012` (Efficiency), `item_000013` (Quickcast). At the end of the test all three supports are in the bag; Longstride can be moved to support index0 using the real transaction. `reuse-fixture.json` records the exact locations.

The report captured movement samples and resource results but did not serialize complete compiled plain/Longstride dictionaries. The test asserted both authoritative profile and exact restoration of the old owned cast; presentation should read/compile the saved fixture through the model rather than treat this report as a full compiled-cast artifact.

## Reproduction and integrity

The original run used Godot4.6.3 at `/usr/local/bin/godot`, headless, with an external60-second timeout and internal45-second watchdog. No import was rerun. Each attempt used distinct Linux XDG roots under `/tmp/godot-m1-v098-runtime-{first,main2,main3}`. Command shape:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v098-runtime-NEW/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v098-runtime-NEW/config \
XDG_CACHE_HOME=/tmp/godot-m1-v098-runtime-NEW/cache \
LONG_STRIDE_REPORT=res://docs/qa/v098-runtime/NEW-result.json \
timeout 60 /usr/local/bin/godot --headless --path . --script tests/long_stride_runtime_test.gd
```

Create the three XDG directories first. Omit `LONG_STRIDE_GROUP` for all sections; set it to `compiler` or `main` to limit a rerun to those sections.

`tested-inputs.json` records final source, relevant production inputs, original first source, fixture hashes and every run's exit code. `oracle-manifest.json` records original d2d188a source hashes and pinned copies. The only changes to each pinned source are removal of its global class name and redirecting the compiler's registry preload to its pinned sibling. Other compiler dependencies are unchanged by the v098 production delta. Logs retain the initial failure rather than hiding it.
