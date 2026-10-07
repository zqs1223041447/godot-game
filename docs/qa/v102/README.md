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
Actual model/button transaction checks are in progress and will be linked here.

Rewards, costs, loot order, save schema, Main, CanonicalGameState, journey rules,
and save transactions remain unchanged. This is source delivery only.
