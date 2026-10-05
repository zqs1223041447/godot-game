# Combat feedback presentation recovery

Rebuilt by the primary developer from v0.45.0 commit
`1b4f9343819d1e0e84336deb94c0728ef41858b8` on 2026-10-05.

The renderer reads `damage_feedback()` without changing combat, RNG, saves,
or the runtime clock. Both legacy and retained foreground paths call it.
The existing damage-number preference also controls the new rows. Normal
hits use parchment, critical hits larger gold text with `!`, and burning uses
copper text with a separate vertical baseline. Player resource loss uses red
and a minus sign. Tiny positive losses remain visible rather than rounding
to zero. At most 48 rows are drawn; age and lifetime come from the runtime.

Rebuilt test: `tests/combat_feedback_presentation_test.gd`, 12 checks, 0 failures,
Godot 4.6.3 headless, exit 0. Coverage: formatting, categories, player marking,
input immutability, fade and expiry. This is a pure presentation-rule test,
not full-game rendering or a Windows frame-rate measurement.

The first launch with default user directories failed before testing because
the data and font-cache locations were not writable. Retrying with writable
XDG_DATA_HOME, XDG_CACHE_HOME and XDG_CONFIG_HOME under /tmp passed.

Per the user's latest direction, native visual review is consolidated with a
future UI batch instead of being a separate gate for each backend revision.
Full-source import and actual gameplay integration remain pending.
