# Return confirmation readability

2026-10-11 UTC; base local49d704c is content-identical to main0484686.

Native Godot4.6.3/OpenGL Compatibility on dot Linux showed dark title text on a dark header and light focused-confirm text on parchment. Local dialog theme now uses a warm brown header with cream title and dark focused/hover-pressed button text. Shared theme, layout, labels, return actions and disabled presentation are unchanged.

Actual-dialog regression:96checks,24failures before;96/96 after. Covers focused/unfocused title frames, normal/hover/pressed/hover-pressed/focus/disabled buttons, focus outline, reopen/dismiss, world revision and shared theme. Map-death return check passes. Theme-color assertions are supplemented by actual native screenshots before/after.

Native after-check observed readable title and focused/hovered confirm text. Tab to Cancel followed by Enter dismissed the dialog and resumed the same exploration run with25remaining enemies. Normal confirmation return and save/exit checked separately. Native renderer is Mesa llvmpipe software; noWindows/FPS/fullsuite claim.

Historical limitations: encounter UI test retains identical3legacy BuildState/API failures before/after; overview retains its baseline schema-count assertion failure. Those tests are not claimed passing.

Screenshots were delivered separately to the owner, not regenerated mockups. Source changes are restricted to the return dialog theme and its new regression test.
