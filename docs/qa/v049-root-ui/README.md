# Targeted reforge UI

Primary-developer work for v0.49, 2026-10-05.

The existing six operation buttons remain. Four targeted families share one
compact selector and one action button, rather than widening the inventory with
four more buttons. The selector reads family names, availability and reasons
from model metadata. The action displays the quoted material cost. No crafting
roll, wallet state or independent rule implementation lives in this UI.

Confirmation names the selected target and cost, and states that all old affixes
will be replaced, other affixes remain random, and a higher tier/value is not
guaranteed. It uses the existing authoritative quote and exact source instance.

Focused checks, each run once:
- controls.log: 17 checks, 0 failures, process exit 0. Covers compact grouping,
  disabled reasons, metadata immutability, exact source/UID capture, target
  changes during a press, interrupted clicks, and legacy/gem-recycling modes.
- actual-ui-flow.log: 14 checks, 0 failures, process exit 0. Uses the real main
  scene, canonical model and inventory panel: legal magic gear, real material
  balance, quote confirmation, Cancel with no mutation, one paid transaction,
  duplicate-confirm rejection, and selector/button containment at 1280×720 and
  2560×1440. Source fixture and user data are isolated under /tmp.

These are headless signal-driven UI tests. They do not claim native mouse-input,
Windows frame-rate or new screenshot verification. No extra native visual run
was made for this compact control addition.
