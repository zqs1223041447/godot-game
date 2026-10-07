# Reward-claim feedback

Baseline: `a45aca0bef2345946c99384243b85218719afb27`.

The existing formal reward transaction already returns the quantities actually
committed (`claimed_shards`, `claimed_gems`, `claimed_flasks`). It can partially
succeed when some categories fit and others remain owed. Main exposes those
counts and the current pending snapshot. No new backend receipt or persistence
state is necessary.

TownServicePanel now uses the successful receipt for the current claim and the
latest world context for the remaining map shards, gems and flasks. A failed
transaction displays its reason and pending quantities, without treating any
result fields as a credit. Button tooltip and a wrapping in-panel status keep
the remaining quantities visible; no new modal is introduced.

The resource cache is reused from the source baseline. With no new asset or
script class, a focused dependency parse passed instead of repeating a full
project import. New runtime strings have all existing font glyphs. Root's
12 presentation checks passed on their first valid execution; the earlier
test-only native-class naming parse failure remains in `../v102-root-ui/`.
Actual model/button transaction checks passed on each group's first run:
59 full-claim, 139 capacity/partial-claim and 64 persistence/reload checks.
The actual TownServicePanel lives in the SceneTree and its button signal calls
the original Main method and canonical transaction; status and feedback are
checked after one deferred frame. The Main object does not execute `_ready()`
or combat, so this is not a full-scene playthrough or native pointer-input test.
See [model and UI evidence](../v102-rewards/README.md).

Rewards, costs, loot order, save schema, Main, CanonicalGameState, journey rules,
and save transactions remain unchanged. This is source delivery only.
