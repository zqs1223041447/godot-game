# v106 monster reference art: technical sample only

This developer branch is retained as a technical sample and backup, pending a new visual direction. These files do not represent user approval of the final art direction or permission to merge to main.

## Scope and result

The independent `tools/export_monster_reference_art.gd` updates only the monster reference PNGs, their art-manifest metadata, and the two missing image headers in the existing reference page. The full reference exporter was not invoked.

- 11 monster templates now link to the four authoritative runtime families
- South-facing idle frame zero is selected through `ActorSpriteCatalog.frame_index(2, "idle", 0)` and `frame_rect`: atlas frame 36, rectangle `[512, 384, 128, 192]`
- Godot `Image.load_from_file`, `get_region` and `blit_rect` perform lossless extraction. Only fully transparent outer rows/columns are removed, followed by an 8px transparent border. There is no resize, recoloring, pixel generation, overlay or new design
- Family PNG sizes: crawler 86×101; skitter 102×107; brute 115×112; rift_warden 110×142
- Each template records its family, source PNG/hash/frame/crop, actual image size and runtime tint. `tint_applied` is false: variants sharing one family intentionally share the same untinted source pixels
- Legacy global `image_size: [128,128]` and `capture` metadata are preserved and explicitly scoped; per-monster dimensions and `monster_capture` override them

## Verification already completed

`export.json` and `verify.json` record 11 nonempty RGBA8 images, exact equality between every saved image's core and the original frame crop, exact expected output bytes, and 8px transparent borders. All four source PNG SHA256 values remained unchanged. The four family PNGs were also visually inspected.

`static-verification.json` records 108/108 passing checks:

- `catalog.json` is byte-identical to baseline `e2fa6db67fb9c4c7f201c795df12bdeb9b699832`
- 72 protected reference files, all 55 non-monster manifest entries, all four source PNGs, and the frozen production Catalog/ActorVisual files are unchanged
- The only HTML edits are the `mist_skitter` and `chaos_guard` header placeholders becoming image tags. Every other HTML byte, including CSS, JavaScript, cards and numeric content, remains unchanged
- All 75 HTML image links and all 66 manifest image paths exist; all 11 monster cards have their correct links
- The saved manifest matches the authority loaded directly by the Godot verifier, and exactly four distinct untinted family images back the 11 templates

No editor import, GPU/window capture, combat run, complete F8 export, commit, push or main merge was performed by this narrow task. These checks are image/data-integrity evidence, not native F8 visual acceptance, gameplay acceptance or a release pass.

## Reproduction commands

Run from the repository root with isolated temporary XDG paths:

```sh
mkdir -p /tmp/godot-m1-v106-reference/{data,config,cache}
XDG_DATA_HOME=/tmp/godot-m1-v106-reference/data XDG_CONFIG_HOME=/tmp/godot-m1-v106-reference/config XDG_CACHE_HOME=/tmp/godot-m1-v106-reference/cache /usr/local/bin/godot --headless --path . --script res://tools/export_monster_reference_art.gd
XDG_DATA_HOME=/tmp/godot-m1-v106-reference/data XDG_CONFIG_HOME=/tmp/godot-m1-v106-reference/config XDG_CACHE_HOME=/tmp/godot-m1-v106-reference/cache /usr/local/bin/godot --headless --path . --script res://tools/export_monster_reference_art.gd -- --verify-only
python3 docs/qa/v106-reference-art/verify_static.py
```

The Python checker only handles JSON, HTML, links and hashes. All pixel extraction and pixel verification are performed by Godot. `--verify-only` reads the art/manifest/page and writes only QA evidence.

The first export succeeded (exit 0) but emitted Godot's generic warning about loading `res://` PNGs directly. The original log remains in `export-attempt01.log`. The tool now passes the globalized filesystem path to `Image.load_from_file`; the subsequent verify run succeeded (exit 0) without those warnings. No import was used to address the warning. Static verification also exited 0; the exit files and original logs are retained beside the JSON evidence.
