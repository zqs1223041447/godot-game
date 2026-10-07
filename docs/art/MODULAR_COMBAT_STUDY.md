# Modular combat study (independent branch)

This opt-in study is based on v111's three completed environment modules and v110's hero presentation adapter. It does not add a formal map ID or change the original map definitions. `tools/run_modular_study.sh` creates a fresh `/tmp/godot-m1-v112-native.*` data directory and runs the existing Main scene through the lawful tier-I old_garden entry. Normal application data is never opened by that launcher.

## What is reused

The original 25-root admission plan, IDs, template/radius/speed/health data, player build, encounter wake-up, combat, projectile, reward and return-to-town code are used. All initial entities exist at entry. Installation validates the original player and every existing monster against the study obstacles before changing geometry. The selected placement needs zero root remaps; installation rejects any colliding root instead of silently moving it.

Only one local module area is added within that isolated run. The rest of the existing 3600×2400 world, roster and progression rules are retained as the test harness. This is not a newly authored complete map or an economy release. Returning to town removes the temporary geometry and character selection; the next ordinary map uses the original layout unless the study installer is explicitly invoked again.

`ModularStudySession.layout()` translates the existing v111 assembly by `bounds.position + (450,1450)`. Body, shadow and sill use the same world foot. The existing alpha PNGs are unchanged. Their source pixels convert to world units once with `1/0.65`; the exported `godot_local_world` collision points are already converted and are only translated. Runtime camera zoom is never applied a second time.

## Shared collision truth

`ModularStudyGeometry` subclasses the existing MapGeometry interface without changing it. Four original polygons, totaling 99 vertices, define an isolated native PhysicsServer2D static space. Godot's convex decomposition preserves the filled contours. Player and monster movement, circle projectiles and radius-zero LOS all query this same space through Main's existing geometry callbacks. Main's player radius remains 15 world units; monster source radii remain unchanged.

The existing sliding and path-selection interface is retained. Polygon bounding boxes provide finite corner waypoint candidates only; they are never collision or rendering truth. Every route edge and legal-point candidate is checked against the real contours. The open arch remains two distinct legs, never a solid rectangle. Installation waits two physics frames and verifies every convex piece is queryable before enabling Main; queries fail closed until ready.

The adapter is limited to four simple contours and 99 vertices. It is not a general map importer or a replacement for a full navigation system. Native collision query precision differs from the historical box calculation; this is deliberate new study geometry, not a claim of bit-identical new combat outcomes. No new damage/reward formula or gameplay clock is introduced.

## Presentation

`DimensionalPropManager.configure_modules()` is selected only for `id == modular_study`. It loads the seven existing PNG layers once per manifest into ImageTextures, preserves mipmaps, and never stretches a module to fit an old rectangle. It validates all resources before replacing live nodes. Failed definitions retain previous nodes and report `diagnostics().study_error`.

Two unsorted ground batches follow the existing floor at global z=-1: shadows first, sill details next. Three module bodies attach by their physical feet at z=0 to the existing WorldDepth. No extra scene collision nodes are created. Fixed 55-degree camera projection, original orientation/light, horizontal receiving ground and XY translation restrictions still apply. There is no arbitrary rotation, mirroring, height change, dynamic lighting or object-to-object shadowing.

The optional hero uses the backed-up eight static AI direction images. Walking and attacks still select idle illustrations; no run/attack animation is claimed. Its contact shadow uses the existing actor contact renderer, not the independent v109 directional projection shader. Other existing actors retain the current main-game presentation.

## Running

Complete this checkout's normal Godot resource import once, then run `bash tools/run_modular_study.sh`. WASD, original combat inputs and town-return UI remain available. The on-screen badge identifies an isolated study. The inherited old_garden title describes the reused admission/progression profile, not an added formal map selection.

A successful startup prints `MODULAR_STUDY_READY`. Native visual observation is recorded separately when available. Existing v111 art/physics evidence is reused; focused adapter and real Main results are under `docs/qa/v112-modular-study`. No Windows export, Release, additional asset download, full historical regression, long soak or frame-rate claim is part of this slice.
