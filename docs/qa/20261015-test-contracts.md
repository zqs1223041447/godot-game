# Current-schema and gem-catalog test contracts

Date: 2026-10-15. Scope: tests only; no production schema, catalog, save migration, or binding behavior changes.

## Reproduced failures

On Godot 4.6.3 stable, each test ran headlessly with a fresh, test-specific `/tmp` XDG data directory and a 90-second timeout:

| Test | Before | Cause |
| --- | --- | --- |
| `canonical_build_store_test.gd` | 39 checks, 1 failure, exit 1 | Current migration was required to equal both `Rules.VERSION` (61) and stale literal 18; its label still said v16 |
| `gem_catalog_test.gd` | 594 checks, 3 failures, exit 1 | Expected 16 supports and 26 icons/definitions; current sources contain 24 supports and 34 icons/definitions |
| `skill_binding_keys_test.gd` | 56 checks, 1 failure, exit 1 | Successful binding flow was required to end at stale schema 59 |

## Corrected contracts

- Canonical legacy migration must persist the current `Rules.VERSION`, produce the same current-version in-memory snapshot, save exactly once, and decode from disk to that exact committed snapshot. The v13 backup filename and byte-exact legacy/BOM backup assertions remain intact. Failure paths retain before-snapshot and disk-byte comparisons.
- Binding starts with a current-schema fixture, captures that initial version, and must preserve it through successful, repeated, rejected, and failed-save actions. Existing full authority snapshots still check failed-save atomicity, cooldowns, RNG, disk bytes, and save counts.
- Gem catalog independently lists the exact expected 10 skill identities and 24 support identities. Sorted equality checks reject omissions, substitutions, and extra source definitions. The exact union must match all 34 emblem identities, and namespaced identities must match all 34 gem definitions. Existing per-definition metadata, texture, footprint, instance-validation, deep-copy, deterministic, and RNG checks remain.

The identity fixtures are intentionally explicit rather than counts derived from production dictionaries. Schema checks compare independently observed persisted/state values against the schema authority, and the binding no-change assertion compares against the captured pre-operation version. Historical migration versions were not globally replaced.

## Verification

| Test | After | Exit |
| --- | --- | --- |
| `canonical_build_store_test.gd` | 40 checks, 0 failures | 0 |
| `gem_catalog_test.gd` | 598 checks, 0 failures | 0 |
| `skill_binding_keys_test.gd` | 57 checks, 0 failures | 0 |

Binding observations remain C absent (`-1`), V = 86, N = 78, M = 77. These are headless input/behavior checks; no visual screenshot claim is made.

Reproduction (run from repository root; each iteration creates fresh user data):

```bash
for test in canonical_build_store gem_catalog skill_binding_keys; do
  case "$test" in
    canonical*) prefix=godot-m1- ;;
    skill*) prefix=godot-skill-binding- ;;
    *) prefix=godot-gem-catalog- ;;
  esac
  xdg=$(mktemp -d "/tmp/${prefix}contracts-XXXXXX")
  mkdir -p "$xdg/config" "$xdg/cache/fontconfig"
  XDG_DATA_HOME="$xdg" XDG_CONFIG_HOME="$xdg/config" \
    XDG_CACHE_HOME="$xdg/cache" BINDING_REPORT="$xdg/binding.json" \
    timeout 90 godot --headless --path . --script "tests/${test}_test.gd"
done
```

`git diff --check` passed for the changed tests. This focused verification does not represent the full repository suite.
