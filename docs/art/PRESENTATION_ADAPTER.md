# Optional hero presentation adapter study

This independent branch is based on main `e2fa6db67fb9c4c7f201c795df12bdeb9b699832`. It adds an opt-in adapter to the existing ActorSpriteCatalog, ActorVisual and RetainedActorLayer. Main still selects its original hero by default. No new character package was downloaded, no map background was replaced, and no gameplay or save rule changed.

## Usage and lifetime

After loading a Main map, read `res://assets/actors/studies/hero_direction_study.json` and pass the parsed Dictionary to `arena.retained_actors.set_hero_presentation(definition)`. The return value is `{ok, error_code, reason}`. An invalid definition leaves the current resource, pose and draw caches unchanged. Pass `{}` to restore the original hero on the same map and the same hero/body/limbs nodes. `RetainedActorLayer.clear()` also releases this temporary selection, so it does not carry to the next map or town. Nothing is persisted.

The catalog prepares the whole definition once before installing it. The normalized entry owns detached frame and clip data; it does not enter the permanent catalog cache. The selected union bounds are used before culling, including while the actor is hidden. Switching invalidates body/contact commands and starts the selected resource's idle pose, retaining facing and already observed gameplay attack IDs. It does not replay an attack or change any gameplay clock.

## Resource contract

The JSON contract is `schema_version: 1`, `coordinate_space: "world"`, with:

- `texture_path`: canonical `res://` PNG resource, already imported by Godot
- `world_units_per_source_pixel`: positive finite authored size, independent of the current camera
- `frames_per_direction`: 1–64; eight directions E, SE, S, SW, W, NW, N, NE
- `frames`: exactly eight times that count, direction-major; each has integer atlas `region: [x,y,w,h]` and region-local `foot: [x,y]`
- `clips`: required idle and optional walk/attack, each `[offset,count]` within one direction; FPS is positive and at most 120. Idle/walk loop; attack holds its last frame. Absent clips use idle. Motion disabled uses idle frame zero
- `contact_shadow_half_size_world`: nonnegative `[x,y]`, at most 256 units each, centered on the actor foot
- Optional `provenance`: source documentation only; not retained or executed by the normalized resource

Regions must fit the actual texture and feet must be within their region, including its border. Unknown root/frame/clip fields and unsupported coordinate spaces are rejected. Readable nonzero-alpha bounds are collected per frame after subtracting that frame's own foot. The union includes contact shadow, the existing ward overlay, and one source-pixel filtering fringe (at least one world unit). The union and silhouette-top anchor are presentation values, never collision sizes.

An animated, offline-rendered 3D atlas can provide multiple frames and clips through this same resource contract. The focused test uses the already available original 144-frame hero atlas to verify the sampling contract. No new model, animation, rig or animation-quality acceptance is implied.

## Coordinates and shadow

The draw destination is `Rect2(-foot * world_scale, region.size * world_scale)` in the existing actor's local world space. The actor root stays at Main's authoritative player position, with scale one, under the existing foot-Y-sorted WorldDepth. WorldCamera alone applies its zoom. No new camera or screen-to-world simulation transform is introduced.

The v109 study was camera-free: one sample scene unit equalled one source screen pixel. Its art scale was 0.115. To preserve that illustration's reference screen height at the main camera's 0.65 zoom, the optional JSON authors `0.115 / 0.65 = 0.17692307692307693` world units per source pixel once. Runtime code never reads 0.65 for resource sizing and never reapplies that conversion when zoom changes. The v109 environment's `screen_pixel` spawn/collider coordinates are not imported into Main; all current map geometry and entity positions remain authoritative.

The optional profile uses the existing concentric contact-ellipse draw routine at the foot, sized from the JSON. It does not reproduce v109's soft two-boot shader or its fixed-direction cast shadow. That long projection depends on the study's fixed lighting and has not been transferred to arbitrary game maps.

## Source and limits

The optional PNG is an exact copy of the AI-generated static mother image already backed up with [v109 shadow study](https://github.com/zqs1223041447/godot-game/commit/0d508207b796353e6eb623e252a1408297928323), SHA-256 `63bcf0d01273f448c44d642f8f3a63e54742762c7bc3119707f391ef2328e4ea`. It uses the same Git blob. Its eight irregular regions and distinct feet match that study. Only idle images exist: walking and attacking requests select static direction images, not animation. The original illustration's directional consistency limitations remain. Source PNG pixels were not edited or resampled.

This branch is an interface and integration study, not a main-game visual replacement or final art approval. Existing weapon-specific appearance limitations remain. No new package acquisition, full F8 export, Windows build, native screenshot, frame-rate benchmark or broad historical test run was performed. Focused results and the initial failures are recorded in `docs/qa/v110-presentation-adapter`.
