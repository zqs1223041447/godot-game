# Short blade basic attack presentation

Primary-developer wording update, 2026-10-05. The short blade base card describes single-target melee basic delivery and its two local-physical consumers. The local weapon summary names ordinary melee attacks and Cleave. The compiled basic preview adds range, target limit and no-projectile wording only for actual melee delivery; legacy basic is unchanged. No layout or artwork change.

Focused headless integration: 7 checks, 0 failures, exit 0, Godot 4.6.3 (`presentation.log`). It uses a real generated short blade definition and actual compiled basic snapshot, checking read-only preview behavior. First attempt used an invalid fixture item ID, so the catalog correctly returned an empty dictionary; the original log is retained. Only the fixture was changed to legal `gear_000561` plus an explicit failure guard, then the affected test reran. No production fix or repeated broad acceptance was needed. No native Windows visual test claimed.
