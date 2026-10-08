# Floating item card wheel routing

Base: `8f324fa99ad06ced2c86575f36993da50064f08c`.

The existing floating card already scrolls its detail body and supports source
to card hover handoff, delayed dismissal, and transparent drag/drop. Its wheel
hit test previously excluded the fixed name/type/TAG header. A real viewport
event over that header left the detail offset at **0** while the underlying
inventory offset became **90**. This could make the item card appear unable to
scroll while silently moving the inventory underneath it.

`ItemHoverCard.scroll_at` now selects the entire corresponding card column,
including its header, and scrolls only that column's detail body. It keeps the
same wheel step, source-item routing and handled-event behavior, including at
the top/bottom limit. Pointer filters stay `IGNORE`, preserving drag/drop and
the existing HUD-owned hover lifetime. No item data, affix rules, saves, layout
sections or other UI panels changed.

Focused verification on Godot 4.6.3:

- New `item_hover_wheel_routing_test.gd`: **29 checks / zero failures** both
  headless and native X11 (Mesa llvmpipe, dummy audio). Uses actual viewport
  wheel events above a separately scrollable inventory. Covers all three
  columns' name/type/TAG/body, long text through the visible final line, upward
  scrolling, bottom-limit isolation, source-item routing, outside inventory
  scrolling, pointer transparency and unchanged presentation data.
- Existing `item_hover_scroll_v37_test.gd`: **10 / zero failures**.
- Existing actual Main/HUD `item_hover_lifecycle_v37_test.gd`: **17 / zero
  failures**, including source entry, another underlying UID beneath the
  transparent card, retention while over the card, exit dismissal, drag and
  inventory close. This uses synthetic engine mouse events, not desktop input.
- Existing `item_hover_card_test.gd`: **227 / two failures**, identical before
  and after this change; its body-wheel isolation and drag/drop checks pass.
  The unchanged failing labels are `current cast preview has its own section`
  (expects old `Text_当前组合施放预览`, while the current section is `Text_当前组合`)
  and `badge layout remains inside the scaled 1080p viewport` (its excessive
  synthetic long TAG exceeds the current header layout). These are recorded
  limitations; this suite is not reported as passing.
- `git diff --check`: passed. No full repository regression or long run.

To run the focused wheel test from the repository root:

```sh
test_runtime=$(mktemp -d /tmp/godot-hover-wheel-XXXXXX)
mkdir -p "$test_runtime/data" "$test_runtime/config" "$test_runtime/cache"
XDG_DATA_HOME="$test_runtime/data" XDG_CONFIG_HOME="$test_runtime/config" \
XDG_CACHE_HOME="$test_runtime/cache" godot --headless --path . \
  --script res://tests/item_hover_wheel_routing_test.gd
```

For native verification, omit `--headless` and use `--audio-driver Dummy` if
audio is unavailable. The Main/HUD lifecycle test requires a fresh XDG path
beginning `/tmp/godot-m1-`.
