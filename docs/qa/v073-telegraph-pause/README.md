# v0.73 local telegraph clock pause

`tests/frost_lock_telegraph_pause_test.gd` checks the optional fourth argument to
`TelegraphedAreaRuntime.advance`: a bounded dictionary of source IDs to the frozen
prefix of the current frame, in seconds. IDs must be positive integers present
in the complete supplied source snapshot. Values must be finite numeric values
between zero and the finite nonnegative frame delta. A nonempty invalid batch
returns no events and leaves all scheduler state unchanged, including states
that would otherwise be cancelled. Empty or omitted dictionaries retain the
previous malformed-input cancellation behavior.

Valid dead, birth-protected, or death-processed sources still cancel their
actions. A living frozen source retains its clock, phase, locked center, packet,
attack identity and Echo pulse count. Partial thaw advances only the remaining
local time and offsets emitted frame deadlines before sorting. The existing
optional `step_time` field contract is retained; Main requests timing for a
nonempty pause batch. This scheduler does not own global status or shield clocks.

## Frozen scheduler baseline

`baseline_runtime.gd` is copied from commit `70b75bc`, file
`scripts/combat/telegraphed_area_runtime.gd`. Its only change is removal of the
first `class_name TelegraphedAreaRuntime` line to avoid registering a second
global class. Its original dependencies are resolved in the current project,
so this comparison isolates scheduler changes rather than claiming a complete
gameplay baseline.

- Original SHA-256: `f89ef26902dbf28b1db465393e33a37ef6f2dd60e24bee5828cc51be75d941b4`
- Fixture SHA-256: `18c8b0298e7b185e0caaa75153edb79dd005d9f395da26d1c1a0f8adb5c21495`

Absent and explicit empty pause calls are compared using Godot's native
`var_to_bytes`, including event shape and dictionary ordering, raw internal
state, exposed state, attack identities, source inputs and the next seeded RNG
draw. Coverage includes ordinary attacks, enemy burn/shock attacks, both older
map bosses and Sunwell Echo; timed/untimed calls; fractional, epsilon-near, fine
and huge delta partitions; and malformed source/delta handling.

Positive pause checks cover ordinary windup and recovery; both Echo warnings
and Echo recovery; copied center/packet/identity and pulse preservation;
chronological ordering and exact ties across paused and unpaused sources;
ordinary and Echo `TIME_EPSILON` behavior; atomic malformed-batch rejection;
death/birth/removal cancellation; and the 100-source/200-pulse bound with no RNG
consumption or caller-input mutation.

## Execution

After the shared project import completes, run:

```sh
bash tools/validate.sh res://tests/frost_lock_telegraph_pause_test.gd
```

The focused suite directly compares the prior scheduler's public entrypoints
and six attack kinds, so the historical scheduler and Echo suites are not
repeated for this isolated change. Final command results and hashes of the
tested inputs are recorded alongside this file in `validation.json` after
execution.

Verified on Godot 4.6.3: **855 checks, 0 failures**, exit 0, no logged engine or
script errors, in 1.308 seconds. All 25 captured input hashes remained unchanged
during the run. `focused-test.log.txt` preserves the engine output. The focused
suite passed on its first run after the shared project import; no historical
suites were repeated.
