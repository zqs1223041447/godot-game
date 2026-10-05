# v051 gem projection local reuse

The production change resolves a valid gem definition once per item projection, instead of three times. No persistent cache, UI change, save change, resource-path change, or trusted-caller API was added.

## Implementation

- `scripts/items/gem_catalog.gd`: `_validated_definition` executes the existing complete envelope, UID, kind, current directory membership, resource, and payload checks, returning its already-resolved definition only on success. Both public `validate_instance` and `metadata_for_instance` use it; metadata attaches the UID to that fresh result rather than resolving the same definition again.
- `scripts/items/unified_item_catalog.gd`: gem projections retain the adapter's stricter outer String-key/type/UID checks, then call the public fully validating gem metadata boundary once. The non-gem validation and equipment/jewel/flask/currency projection branches retain their original logic.
- `ResourceLoader.load` and returned Resource reference semantics are unchanged. Definition containers remain detached, and current support membership is checked on every call. No result survives a call in a new cache.

## Frozen-source verification

Original catalogs were captured before editing from source `7b1642d471872cfa6a24a7c897352db181915320`:

- `tests/fixtures/v051/gem_catalog_before.gd`: only its class name was renamed
- `tests/fixtures/v051/unified_item_catalog_before.gd`: only its class name and Gems preload destination were changed to point at the frozen gem catalog

Reversing those fixture-only substitutions exactly reproduces both recorded original SHA-256 values in `frozen-sources.json`. `candidate.patch` records the final production difference against those originals. `after-source-sha256.txt` records the tested production files, test, and fixtures.

One isolated headless run of `tests/gem_projection_reuse_test.gd` completed with **exit 0, 232 cases, 1643 checks, and zero failures**. The raw `test.log` contains no script/runtime errors. The probe does not load main, canonical game state, or user saves, and it does not simulate combat or render UI.

Checks include:

- Every current skill/support definition and valid instance against frozen output
- Exact recursive Variant types and container content, including bool/float/int distinctions
- Null and malformed outer shapes; missing/extra fields; malformed UID values and boundaries; Unicode IDs; StringName wrapper keys and payload keys
- Malformed/unknown definition IDs, kind mismatch, bool/float/string and invalid level/quality values
- Removal and restoration of every current support registry entry, with immediate rejection/restoration at public boundaries; registry membership without a source provider remains invalid
- Deep mutation of returned arrays/dictionaries followed by unchanged re-projection; original inputs remain unchanged
- Actual Texture2D resource identity and original texture resource paths, without mutating Resource objects
- Existing fixed/rolled equipment pools and rarities, regular/special jewels, both flasks, and currency projection paths
- Unchanged global RNG

Source textures are held only by the test's comparison catalog, preventing repeated test-only decoding while comparing actual resource identity. This does not introduce a production cache.

## Scope and remaining performance evidence

This is a pure correctness comparison, not a timing benchmark or rendered pixel comparison. The parent task owns the production main/HUD first-I after comparison and integration checks. Existing catalog test suites were not rerun by this worker, preserving the assigned serialized CPU window.

The earlier independent component probe showed support-gem projection dominating its standalone fixture, but it had different texture owners than the actual main/HUD process. Do not substitute those standalone timings for production first-I latency or claim a theme optimization from this change.

## Reproduction

```bash
probe_root=$(mktemp -d /tmp/godot-m1-v051-gem-reuse-XXXXXX)
export XDG_DATA_HOME="$probe_root/data"
export XDG_CONFIG_HOME="$probe_root/config"
export XDG_CACHE_HOME="$probe_root/cache"
export GEM_PROJECTION_REUSE_OUT="$PWD/docs/qa/v051-gems/result.json"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot --headless --path "$PWD" --script res://tests/gem_projection_reuse_test.gd > docs/qa/v051-gems/test.log 2>&1
probe_exit=$?
printf '%s\n' "$probe_exit" > docs/qa/v051-gems/exit-code.txt
```
