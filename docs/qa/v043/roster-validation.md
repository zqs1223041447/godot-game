# v0.43 camp roster and state validation

Scope: `MapCampState`, its pure catalog dependencies, and compatibility with
`MapCampLayout` output. This evidence does not cover scene movement, trigger
interaction, runtime factory admission, graphics, performance or Windows play.

## Result

Godot 4.6.3: **8,755 checks, 0 failures**. The check count mainly includes
per-root catalog comparisons and permutation assertions; it is not a count of
gameplay scenarios. The reference comparisons cover **24 legal profile/special
configurations and 2,196 root selections** across seeds 0, 43 and -1701.

- All six normal progression tiers and both fixed test profiles generate the
  full 24/36 roster before activation, in west/north/east admission order
- Same seed and profile produce byte-identical rosters. Every ordinary entry
  matches separate calls to the existing ordinary-roll, elemental selection
  and special-override authorities. Fixed ember slots preserve empty overrides
  and do not advance the ordinary RNG
- Natural samples preserve white, blue and rare rolls, splitter/brood templates
  and naturally normal frost/storm templates. No rarity promotion is introduced
- All six activation orders retain identical rosters and final states; two or
  three groups may remain active together
- Partial, duplicate, reused, nonpositive, float, bool and otherwise malformed
  root IDs reject atomically. A cleared group cannot activate again
- Unknown/descendant and non-integer death keys do not count. Only registered
  root membership determines each camp's active/cleared projection
- Invalid initial/replacement profiles, seeds, records, counts or non-finite
  geometry leave the entire prior checkpoint byte-identical
- Caller-owned profiles, landmarks, root arrays, entries, state projections and
  checkpoint copies cannot mutate helper authority
- Helper calls preserve global RNG; a caller RNG passed as an invalid seed is
  rejected without consuming it
- Actual `MapCampLayout` output is accepted at the arena origin and a translated
  origin for every baseline profile, preserving every roster position exactly

## Reproduction and evidence

Run from the repository root:

```sh
python3 docs/qa/v043/roster-run.py
```

The runner copies only the test and its referenced scripts/data into a temporary
project, sets separate Linux XDG data/config/cache directories, and invokes the
single script directly. It does not import the whole project or touch player
saves. Generated temporary files are removed when the runner finishes.

- `roster-test.log.txt`: final passing log
- `roster-tested-files.json`: exact tested-file SHA-256 hashes and process result
- `roster-first.log.txt`: earlier passing pure-helper run, 8,176 checks
- `roster-layout-first.log.txt`: preserved parse failure when actual-layout
  coverage was added; fixed by explicitly typing a detached Dictionary variable

The final passing run includes that fix. No production helper change was needed
after the first passing run.
