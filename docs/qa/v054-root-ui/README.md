# Faster burning preview

Primary-developer text implementation, 2026-10-05. Adds one compact line only when the authoritative `burn_profile.burn_faster` is nonzero. It explains faster settlement and reduced duration with the same theoretical single-application total. The displayed duration, DPS and total are read from the compiled profile and never recalculated here. Fire DoT additive specialization stays on its own line. Missing or zero faster values preserve the previous wording exactly.

After the shared import, one headless test run passed 9 checks, 0 failures, exit 0, no ERROR output, Godot 4.6.3 (`preview.log`). It covers unchanged zero text, final duration, unchanged supplied total, combined modifiers, read-only behavior and disabled profiles. Actual model/compiler/runtime coverage belongs to the main integration batch. No layout/artwork change or native Windows visual acceptance claimed.
