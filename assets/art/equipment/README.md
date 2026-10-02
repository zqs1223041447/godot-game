# Painted equipment objects

Twenty-one original transparent game assets: 17 equipment definitions and four jewel bases. Generated with the built-in `image_gen.imagegen` tool from the approved magical field-journal style reference. No equipment pixels were cropped from the reference.

`generation-prompts.json` preserves the complete prompts. `manifest.json` records the reference identity, source output filenames, byte hashes, dimensions, alpha coverage, and runtime import settings. Source PNGs are preserved byte for byte.

The runtime entry point remains `EquipmentArt.draw_item`. Its presentation-only painterly helper resolves equipment `base_id`/`id` and jewel `base`, measures alpha content once, caches the texture, and fits the object inside the caller's rectangle without changing layout or item data. Empty-slot hints and unknown/missing assets retain the procedural fallback. Each PNG import is capped at 512 pixels with mipmaps for the 42-pixel inventory grid and 108-pixel detail display.

Run the focused renderer gate after Godot imports the assets:

```
godot --headless --path . --script res://tests/equipment_painterly_art_test.gd -- --require-all
```

The existing `equipment_art_test.gd --capture` native sheet also uses the actual painterly dispatch. Inventory cells preserve item dimensions: weapons 1×3, armor 2×3, charms and jewels 1×1. Painting does not encode item rarity; existing borders, badges, and tooltips remain authoritative.
