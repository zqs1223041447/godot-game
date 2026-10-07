# Static art study source audit

Audit date: 2026-10-07 UTC. This record preserves a completed read-only review of the original environment and independent Godot sample. No Blender/Godot process, rendering, or asset download was performed for this audit. It is provenance and portability evidence, not game integration or animation acceptance.

## Result

The environment uses nine identified Poly Haven asset families. All nine have official CC0 asset pages; no unknown environment-asset license was found. [Poly Haven's asset license](https://polyhaven.com/license) and [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) are the governing asset-license references. This statement does not extend CC0 to the AI-generated character image or the SIL OFL font.

Direct binary inspection of the final compressed scene found 40 Image data blocks with 40 complete embedded image buffers, totaling 25,514,871 bytes. There were no linked Library blocks, Text blocks, fonts, sounds, MovieClip, Volume, or CacheFile blocks. All 40 Image source-path fields were relative //assets paths. Packed-image metadata retains old workspace asset paths, but those are not observed external file dependencies.

The original 77-entry delivery-file-checksums.json was independently recomputed: all SHA-256 entries matched. The existing download audit reports 54 complete-file MD5 matches and records 15 bounded tree ranges with SHA-256 and Content-Range. The full original tree-buffer MD5 was deliberately not claimed for the edited subset.

## Official sources and credits

- [modular_fort_01](https://polyhaven.com/a/modular_fort_01): Rico Cilliers. Authored gate, walls, buttress, and modified fallen masonry.
- [fern_02](https://polyhaven.com/a/fern_02): Rico Cilliers (Modeling); Rob Tuytel (Scanning). Four fern-clump variants, instanced at edges and wall roots.
- [rock_moss_set_01](https://polyhaven.com/a/rock_moss_set_01): Kless Gyzen. Framing rocks, stones, and smaller rubble.
- [forest_ground_04](https://polyhaven.com/a/forest_ground_04): Rico Cilliers (Minor Adjustment); Rob Tuytel (Photography, Processing). Ground soil/gravel diffuse and normal layers.
- [aerial_grass_rock](https://polyhaven.com/a/aerial_grass_rock): Rob Tuytel. Ground grass/moss diffuse and normal layers.
- [medieval_blocks_05](https://polyhaven.com/a/medieval_blocks_05): Rob Tuytel. Localized old approach diffuse and normal layers.
- [grass_bermuda_01](https://polyhaven.com/a/grass_bermuda_01): Rico Cilliers. Instanced grass blades at selected banks.
- [shrub_02](https://polyhaven.com/a/shrub_02): Rico Cilliers. Sparse edge shrubs and wall-root foliage.
- [tree_small_02](https://polyhaven.com/a/tree_small_02): Rico Cilliers. Original trunk/branches plus 120000 original leaf triangles, re-instanced into two edge framing groups.

The original SOURCES.md adds Rob Tuytel (photography) to Grass Bermuda 01. Its [official asset page](https://polyhaven.com/a/grass_bermuda_01) inspected on the audit date lists only Rico Cilliers. Remove that extra attribution unless another primary source supports it. The other eight credit entries agree with their official pages.

Tree Small 02 is an edited subset: original trunk and branches plus 120,000 original leaf triangles, with leaf geometry re-instanced to frame the scene. It is not the complete unmodified tree.

## Identity and license details for the Godot sample

- The environment PNG is byte-identical to the final Blender render: SHA-256 89a1e4ae4aa419df79fea42a6f8ab8abc365f18a85db8fb6166daed083d5f4ab
- The hero PNG is byte-identical to the supplied imagegen original: SHA-256 63bcf0d01273f448c44d642f8f3a63e54742762c7bc3119707f391ef2328e4ea. It is a static idle direction master image, not a 3D character or an animation deliverable
- Arena Sans SC matches the project's font byte-for-byte: SHA-256 8e84c0eaf389a86424df39a7e162519de7bd63297fc97679089a4d2a522e5ccc. Embedded copyright is Adobe 2014–2021; the embedded license is SIL OFL 1.1
- The original independent Godot folder lacks a companion font-license file. Include the existing project assets/fonts/OFL-NotoSansCJK.txt, SHA-256 849f4ea9c214fa4ac3593b770c699f387534b11ce671264c1b10d85bdcb5997b
- Preserve all three asset .import settings files. Both PNGs explicitly enable mipmap generation; .godot is a regenerable cache
- project.godot has no configured main scene. Document launching the sample with --script res://preview.gd

## Compact-archive corrections

1. Retain the packed blend, final render, source/license record, projection mapping, final verification, download audit, and original checksum evidence. Create a separate checksum inventory of files actually included in the compact archive.
2. The original 77-entry checksum evidence includes intentionally omitted raw assets. Label it as the complete research-source history, not the compact archive's file inventory.
3. build_scene.py already resolves its paths relative to itself, but requires the raw assets/ tree. Preserve it as a construction recipe and state that rebuilding from glTF requires retrieving the omitted sources. Opening or rendering the packed blend does not require that raw tree.
4. The original verify_scene.py writes its report and saves/overwrites the blend on line 13. It is not a read-only validation entry point. Omit that save behavior.
5. select_tree_data.py is a reusable optional acquisition recipe. If retained, include sources/tree_small_02-files.json and sources/tree_small_02_original.gltf.json. It performs network reads and writes derived files.
6. inspect_fort.py, inspect_nature.py, inspect_greenery.py, and preview_gate.py are one-time research tools. They are not needed for the compact artifact.
7. The original archive ZIP, .blend1 backup, fort-inspect.blend, raw environment downloads, caches, logs, and intermediate renders can be omitted.

## Repeating the structural check

inspect_blend.py implements the already successful in-memory BHead/SDNA inspection method and emits JSON to stdout. Use Python 3 and the zstandard package for this compressed file:

    python verification/inspect_blend.py PATH/TO/sunlit-ruins-environment.blend

The script reads the scene, checks actual embedded image-buffer lengths, counts linked/external data-block types, and identifies asset families from relative image paths. It never launches Blender, renders, writes the scene, or extracts textures.

The saved script was prepared from the successful inline method and was not re-executed while preserving these findings. No 77-file hash sweep was repeated at this step.

## Scope limits

The inspected .blend is 43,434,283 bytes, SHA-256 b9f9ec71ff24d593bbe85b6294aeca24e2d0ca86ddea6370206bb2bdb127ffd7. Binary inspection establishes the dependency facts above; it does not establish visual correctness, runtime performance, collision, animation, or game integration.

A scoped pattern scan of the source explanations, root JSON evidence, Python scripts, and source metadata found no suspect credential fields, authorization headers, secret/token links, or private absolute paths in those text files. Credential values were not sought or printed. The scan is not a blanket secret-scanner guarantee.
