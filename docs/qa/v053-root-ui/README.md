# Fire damage over time preview

Primary developer, 2026-10-05. The existing burn preview adds one line only when the authoritative `burn_profile.fire_dot_multiplier` is nonzero. It displays the additive percentage and explicitly says it is already included in the displayed DPS/total. No damage is recalculated in presentation, and absent/zero modifiers preserve the original lines exactly. No layout, artwork or font-size change.

After the shared import, one focused headless run passed 9 checks with 0 failures, exit 0, no ERROR output (Godot 4.6.3); see `preview.log`. This covers unchanged zero behavior, positive and combined values, input immutability and invalid/disabled profiles. Actual compiled/model integration is covered by the main batch rather than duplicated here. No Windows native visual check is claimed.
