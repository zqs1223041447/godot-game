# Independent talent details focus review

Verdict: PASS for this focused local fix; no blocking findings. No repository edits, staging, editor import, or remote actions performed by this review.

## Scope and correctness

Read AGENTS.md and docs/ACTIVE_WORK.zh-CN.md. Production diff is exactly one added line, enabling follow_focus on the existing inner talent-details ScrollContainer. No layout, model, transaction, save, focus-order, or gameplay source changes occur. git diff --check passed.

The test loads real main.tscn and sends Tab press/release InputEventKey events to root.push_input. Only the initial search field is directly focused. Expected detail controls are compared against the actual focus owner in forward and reverse order; navigation returns to search. Five real variants (allocated start 58833, available 15144, mastery 89, socket 6230, source-stat-length-selected description 861), nine supported UI/font pairs and two close/reopen cycles produce 90 matrix cells. Hidden/visible panel state is checked; mastery/socket availability and action inclusion guard against an empty traversal.

Geometry checks cover every clipping ancestor, subtract visible scrollbar space, require full styled content and control center visibility, and allow at most one scaled local integer-scroll unit plus 0.001 for vertical border quantization. This is narrow and meaningful; strict content checks are not replaced by the tolerance. Outer panel scroll must remain zero.

Snapshot and persistence checks cover complete canonical state, canonical/practice save presence and bytes, settings presence and bytes, per-scale presentation preferences, arena/global RNG, run revision and cooldowns. Scale settings are deliberately assigned by the fixture; the preservation assertion concerns navigation at each assigned scale. The test does not activate allocation/refund/socket operations.

## Independent execution

Godot 4.6.3.stable.official.7d41c59c4 on Linux. Each invocation used a new /tmp/godot-talent-focus-review-* directory and independent XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME. Both used timeout 90 godot --headless --path . --script tests/talent_details_focus_test.gd; negative appended -- --disable-follow-focus. Internal watchdog is 80 seconds.

Positive process exit 0; negative process exit 1 (expected).
- /tmp/talent-focus-independent-positive.log: 90 matrix cells; SCRIPT ERROR count 0; Talent details focus: 5219 checks, 0 failures
- /tmp/talent-focus-independent-negative.log: 90 matrix cells; SCRIPT ERROR count 0; Talent details focus: 5219 checks, 1420 failures

Negative failures by category: {'border within one scroll unit': 456, 'full content inside': 440, 'interactive center inside': 384, 'content inside logical viewport': 140}. No other failure category. Thus the negative is nonvacuous and demonstrates lost visibility rather than a synthetic assertion on follow_focus alone. Both matrices complete all 90 cells.

## Documentation and limitations

Reviewed docs/qa/20261015-talent-details-focus.md. Its main positive/negative counts match independent reproduction and scope statement is accurate. Its adjacent-test counts are worker-reported evidence; this reviewer did not independently rerun those two adjacent tests. This is focused headless logical 1280x720 coverage, not Windows rendering, screenshots, native 2K layout, full-suite acceptance, or remote delivery.

Workspace contains numerous pre-existing untracked .uid/.import sidecars outside this patch; they were not edited or staged. Keep them out of any scoped commit. Existing remote-publication cancellation/blocker is outside this review and remains unchanged.

## Reviewed SHA-256

- scripts/ui/canonical_passive_panel.gd: d3ca6797374c0835eb4d3418b21d9cc9050b2f5727fb3b8de755c2331190d437
- tests/talent_details_focus_test.gd: 13e24069ddedd0878eb5939a3759f1d216a59bdba7fa9fcf611cef9554479c9c
- docs/qa/20261015-talent-details-focus.md: 8744412b249916cb1e3e81f7e9b683aaa38ffe4427e364f6af43ecc059337f60
