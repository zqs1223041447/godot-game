# Independent pause/settings focus-scroll and encounter contract review

Date: 2026-10-15 UTC. Checkout: /workspace/scratch/a51485f153de/godot-game. Base: a0b794c. Reviewer made no production/repository edits, imports, staging, commits, remote writes, or branch changes. Review and probe artifacts only were written under /tmp.

## Scope and conclusions

The initial pause-only production change was correct and independently verified. A separately authorized real-Tab settings probe then established the same genuine offscreen-focus defect in four of nine supported font/UI combinations. Root explicitly expanded this local batch to pause and settings. Final production diff is only a comment and `scroll.follow_focus = panel_name in ["pause", "settings"]` in the shared PanelScroll constructor. Other panels retain disabled follow-focus; all overlay windows are built at startup, so scope assertions are not vacuous. No component behavior, encounter definitions, transactions, or data logic changes.

The component fixture replaces stale aggregate-neutral-multiplier text assertions with exact selected compiler definition descriptions. It covers empty, six singles, all 30 ordered distinct pairs, canonical ordering, explicit flat +80 armour and unmodified-health shield units, and health/shield order independence. It does not call the UI summary helper to construct its oracle. Existing invalid/disabled/detachment, metadata, real clicks, repeated keyboard activation, in-flight context changes, state/save/catalog/RNG invariance remain. Removal of the old <500px total-height cap is justified: the six-option content legitimately scrolls. Its replacement verifies every visible label, option, description and confirmation can be revealed in a real 480px ScrollContainer at 220/280 logical width and all supported font scales, retaining child bounds and complete wrapped-line checks.

Pause regression uses actual Tab/Shift+Tab from one initial focus and actual pointer events at keyboard-reached coordinates; no programmatic target reveal conceals the original bug. Settings likewise traverses all seven controls forward/back, requiring scrolling only when controls were genuinely offscreen. Clip rectangles exclude visible scrollbar area and allow at most one logical pixel of rounding. Both test real Main with canonical state and supported practice entry, and preserve save bytes, full build snapshot, run revision, encounter selection, scene/global RNG; settings additionally preserves preference values and presentation file bytes.

The two requested physical window sizes retain an explicitly asserted 1280x720 logical viewport under canvas_items. The standalone component deliberately establishes a 720x720 logical viewport. Claims are headless logical geometry/input-routing acceptance, not independent 2K logical layouts, screenshots, native Windows rendering, FPS, or full-suite acceptance. Historical QA clarifications accurately distinguish physical request sizes from logical coordinates.

## Review feedback resolved

- Added explicit observed logical viewport assertions and scrollbar-excluded clip bounds
- Verified all unrelated overlay windows are actually constructed before scope checks
- Negative controls originally retained their disabled flag into the next matrix cell, generating irrelevant production-property failures. Final tests restore the original flag only after all cell input and assertions, isolating negative failures to the actual focus/scroll/pointer defect

## Independent evidence

All invocations used a distinct fresh /tmp/godot-* XDG data/config/cache root, `timeout 90 godot --headless --path . --script ...`, no editor import. Godot 4.6.3.stable.official.7d41c59c4.

- Component final: 3918 checks, 0 failures, exit 0. /tmp/encounter-controls-review.log
- Final pause: 1070 checks, 0 failures, exit 0. /tmp/review-final2-pause-positive.log
- Final pause disabled-follow-focus negative: 1070 checks, 450 expected failures, exit 1. /tmp/review-final2-pause-negative.log
- Final settings: 1025 checks, 0 failures, exit 0. /tmp/review-final2-settings-positive.log
- Final settings disabled-follow-focus negative: 1025 checks, 36 expected failures, exit 1. /tmp/review-final2-settings-negative.log
- Positive logs contain no SCRIPT ERROR, ERROR or WARNING; negative logs have no SCRIPT ERROR or WARNING and no carryover production-property failures
- Final git diff --check passes

Verdict: PASS, no blocking findings in the reviewed scope. Focused checks are not a full regression run. Earlier reruns are superseded, not additive independent coverage.

Initial independent settings probe: /tmp/settings-focus-review.gd and /tmp/settings-focus-review.log. At logical1280x720, Reset/Back clipped at UI1.1/font1.0–1.2 and UI1.0/font1.2; Motion additionally clipped at UI1.1/font1.2. With instance-only follow_focus=true, all nine scale combinations had no clipped controls. Genuine scrolling was 11/43/13/79 in those combinations, versus zero in the unfixed case. This was evidence for the scoped extension, not an unsolicited production change.

Existing untracked generated .uid/.import sidecars were already present before this review and were not edited or added by the reviewer. Selective staging/file-tree verification remains root responsibility. No publication was attempted.
