# Independent skill-binding focus review

Verdict: PASS for the scoped local fix and headless logical-geometry regression. No blocking findings.

Reviewed branch `dot/20261015-skill-binding-focus`, baseline/HEAD `554ce88852560afbc889e772e4c7a747cdaba6a5`, on 2026-10-15 UTC. No repository edits, imports, staging, commits, remote operations, or publication performed by this review.

## Scope and static findings

- The complete tracked production diff is one insertion: `_rows.follow_focus = true` in `CanonicalSkillPanel._build()`. `SkillGroupRows` and its intentional gem-slot `Control.FOCUS_NONE` remain unchanged.
- The test uses real `main.tscn`, canonical model, supported equipment transaction to obtain capacity 11, and real binding controls. It does not fabricate the capacity or navigation snapshot.
- The vertical border allowance is explicitly `abs(rows.get_global_transform().get_scale().y) + 0.001`. This means one local integer scroll unit transformed into logical space; it does not silently relabel 1.1 logical pixels as one logical pixel. Horizontal allowance is only 0.001.
- Content-region geometry is derived separately from the actual normal StyleBox content margins. Current action style has four local units of top/bottom inset. Content-region and interactive-center assertions use strict scroll clip and logical viewport containment, without the border tolerance.
- Forward and reverse navigation dispatch actual Tab/Shift+Tab events after only initial focus seeding. Each step asserts the expected focus owner. Enter opens the bottom OptionButton. Escape goes through `Input.parse_input_event` with the appropriate window ID. Popup visibility must become false before reverse traversal; a still-open popup causes immediate failure and exit. There is no synthetic selection callback or programmatic hiding used as an input substitute.
- The regression compares full model snapshots, canonical and practice save bytes, settings bytes, scene and global RNG, run revision, cooldown ledger, and each matrix cell's presentation preferences. Negative injection restores follow_focus after each cell.
- The QA correctly limits claims to headless Linux Godot 4.6.3 and actual 1280x720 logical viewport under physical window settings 1280x720 and 2560x1440. It does not claim native 2K geometry, Windows validation, performance improvement, or pixel-perfect border enclosure.

## Independent executions

Each invocation used a newly created `/tmp/godot-skill-focus-review-*` XDG data/config/cache root and `timeout 90 godot --headless --path . --script tests/skill_binding_focus_test.gd`, plus the indicated user arguments. No editor/import invocation was used.

| Arguments | Checks | Failures | Exit | Completed matrix cells |
|---|---:|---:|---:|---:|
| none | 3303 | 0 | 0 | 18 |
| `--capacity11` | 3629 | 0 | 0 | 18 |
| `--disable-follow-focus` | 3303 | 326 expected | 1 | 18 |
| `--capacity11 --disable-follow-focus` | 3629 | 506 expected | 1 | 18 |

No script errors occurred. Negative-control failures are exclusively visibility and scrolling failures:

| Category | Capacity 10 | Capacity 11 |
|---|---:|---:|
| Border enclosure | 62 | 98 |
| Content within clip | 62 | 98 |
| Center within clip | 58 | 94 |
| Content within viewport | 54 | 90 |
| Center within viewport | 54 | 90 |
| Downward scroll | 18 | 18 |
| Reverse upward scroll | 18 | 18 |

There are no negative-control focus-order, popup-opening, popup-dismissal, state/save/settings/RNG, or follow-flag restoration failures. Therefore the negative result measures the intended scroll defect rather than invalid traversal behind an open popup. Positive logs contain no ERROR/WARNING lines. `git diff --check` passed.

Logs: `/tmp/skill-binding-review-positive10.log`, `/tmp/skill-binding-review-positive11.log`, `/tmp/skill-binding-review-negative10.log`, `/tmp/skill-binding-review-negative11.log`.

Reviewed file SHA-256:
- tests/skill_binding_focus_test.gd: bfbed1f743d36fa712aabf34b5696953865004d57c655720fc8a3b7a13be8b6e
- docs/qa/20261015-skill-binding-focus.md: 53ee55d2d26f4ec6afc9ad4e969113ff4d310359c8e8fe5405c03be5612252f5
- scripts/ui/canonical_skill_panel.gd: 782977c81e97421c44c6f13af007a35fee5c016089e95f783791304f3b705489

Existing component regressions in the author's QA were not independently rerun in this review. This is focused acceptance, not full-suite certification. Remote publication remains a separate blocked action pending renewed permission.
