# Exploration cleanup guidance

Prepared independently from `d7e4121ddff09624de796f7857520926bd610d4e`.

The existing six outpost flags and cleared-count display do not locate enemies
that have pursued the player away from their original positions. The new Main
query derives a detached presentation snapshot from current live actors, their
root lineage, and the existing descendant queue.

- More than five live actors: show an uncleared-outpost overview
- One to five: select the closest current position; exact distance ties use the
  smaller actor ID. Report an eight-way bearing, or `here` for exact overlap
- Boss descendants retain their boss lineage but are not labelled as the boss
- No live actor with queued descendants: show a waiting state without a position
- Physically cleared but completion save pending: show `settlement`, not success
- Successfully completed or returned to town: use the existing return controls
  or remove the hint

This bearing is not a walkable-path or line-of-sight claim. The query does not
wake, move, spawn, kill, or modify enemies and does not draw RNG or save data.
HUD polls every 0.2 seconds without catch-up bursts; world-mode changes refresh
immediately. Ordinary world events do not force an additional query. Each query
uses two bounded live-actor traversals (capacity 100), one existing queue pass
(capacity 64), and the six outposts' root identities. No new combat timer,
persistent cache, map reveal state, or schema is introduced.

One shared import passed. Root HUD checks passed 22/22 on their first run.
The three Main scenario groups passed 286 checks; two isolated runs also
performed four startup checks each. The original fixture's stale-schema and
missing-wall errors are retained, and only its affected query group was rerun.
See [runtime-validation.md](runtime-validation.md). All new runtime strings have
bundled glyphs; the font is unchanged. This batch does not rerun historical
combat suites, regenerate the reference catalogue, or export a package.
