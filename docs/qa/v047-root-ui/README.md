# Ember proliferation presentation

Primary-developer implementation, 2026-10-05.

- Original hand-painted bronze/ember icon uses actual RGBA transparency; bytes
  copied unchanged from built-in image generation. Prompt/provenance and SHA256
  are in the grimoire asset manifest; alpha statistics are in asset-verification.json.
- Standalone gem card separates function, compatibility/exclusion, base values,
  and damage/mana modifiers. Base values read the authoritative support and spread
  policies. Compatible active skill names are not added to TAGs.
- Compiled skill preview reads actual role DPS and spread metadata. Adds two
  lines only for proliferation: radius/target bound/walls, and preserved remaining
  duration/single hop. Existing Ignite preview is unchanged.
- One integrated presentation check after shared import: 15 checks, 0 failures,
  process exit 0, Godot 4.6.3, no ERROR output. Covers the actual canonical model,
  registry, compiler, and read-only display. See presentation.log.
- This is not a Windows hardware or native visual test. Visual review is
  consolidated with a UI batch; no separate per-version screenshot gate.
