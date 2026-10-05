# Shock presentation

Primary-developer implementation, 2026-10-05.

- Original warm bronze lightning talisman with golden gem, generated using the built-in image tool and copied unchanged to `assets/ui/grimoire/shock.png`. Prompt/provenance/hash are in the grimoire asset manifest. Actual transparent alpha is verified in `asset-verification.json`; the black viewing backdrop is not embedded artwork.
- Standalone support card separates the function, compatibility, two authoritative policy values (duration and damage taken), refresh/non-stacking limits, and damage/mana tradeoffs. Compatible active names remain outside TAGs.
- Compiled preview reads `shock_profile` and adds two compact lines only when enabled. Wording makes clear that newly applied shock does not retroactively amplify the applying hit and does not affect damage over time.
- After the shared clean import, one integrated presentation run passed 19 checks, 0 failures, process exit 0, no ERROR output, Godot 4.6.3. See `presentation.log`. Covers canonical gem presentation, authoritative policy values, compiler integration for bolt/nova/chain, disabled/absent profiles and read-only behavior.
- No layout or type-size changes. This is not a native Windows or hardware frame-rate validation. No separate per-version screenshot gate was added.

## Runtime status cue

A single muted-gold lightning polyline is drawn beside each affected actor, separated from the existing ember marks. It consumes detached `shock_statuses()` records through both arena drawing paths and the retained foreground adapter. No aura, particles, status text, damage calculation or RNG was added. The same one-mark cue remains in low effects mode. Drawing is capped at 101 unique player/monster targets and ignores malformed or expired rows.

One focused renderer command test passed 18 checks, 0 failures, exit 0, no ERROR output (`status-renderer.log`). It covers bounded geometry, identity deduplication, input/output isolation, invalid/expired rows, foreground fallback and renderer linkage. No claim of native Windows visual validation is made.
