# Camp aggregate compatibility: native-only map entry

Base: `7918f5040db07c99d583d2cffb5b15965e90986b`.
Only `tests/map_camp_admission_test.gd` and this `compat-camp-*` evidence are
changed by this work. No production, Main, combat, rendering, import, asset,
save, or broad-suite execution was added.

## Result

Godot 4.6.3, headless, isolated XDG paths:

- Final attempt02: **51,605 checks, zero failures, exit 0**
- Historical four-map branch: **22,326 checks, zero failures**, 340 primary
  staged groups and 240 rejected groups
- Native branch: **29,279 checks, zero failures**, 360 primary staged groups
  across 90 lawful profiles and 46 rejected groups (including two rectangle
  fallback cases). Repeated detached plans additionally check identity advance
  and isolation after an explicit test-owned checkpoint commit
- Total: 700 primary staged groups and 286 rejected groups

The explicit old-map list retains the original nested modifier/tier loops and
all their assertions. The original `_runtime`, `_geometry`, `_entries`,
`_boss_entry`, `_positive`, `_reject`, `_failures`, and `_boundary_checks`
functions are byte-identical to the base. The original preserving helper has
only an optional `prepared = null` parameter and its pass-through; every old
check and default call remains unchanged. Input manifests record the static
byte-preservation verification.

## Native coverage

The new entry is exercised separately; it is not skipped or treated as a
historical rectangle map.

- Read actual `NativeSession.layout` assembly and formal new-map landmarks
- Install the four native contours and 99 original vertices, wait two physics
  frames, and require the actual per-piece physics readiness predicate
- Prepare the real fourteen-segment route result; verify each endpoint and
  forward/reverse native sweep at radius 36, or 51 for the four detour legs
- Use typed `PreparedMapEntry`, attached to the exact native geometry object,
  ready with those real routes and in active use
- Exercise all three actual source camp groups and the boss for 90 profiles:
  10 tier-I profiles at wave 1, 30 tier-II profiles at wave 4, and 50 tier-III
  profiles at wave 8. Selections include no modifier, each of six normal
  modifiers, the original three two-normal combinations, and every special
  modifier allowed by its actual wave gate. Sixty disallowed selections are
  explicitly checked as compiler rejections
- Use actual deterministic `MapCampState` rosters and current monster policy,
  not remapped or synthetic positions. Actual frost, storm, and chaos template
  replacements are observed (80, 60, and 40 actors respectively)
- Compare every admitted actor field and the complete checkpoint against the
  real `Admission.create_root` factory. Verify exact IDs, positions, waves,
  radii, delay, modifier source metadata, root lineage, pending descendants,
  prior traces, checkpoint detachment, and post-commit ID advance
- Require the exact new `ruins_garden_slam` boss attack and actual boss resolver
  map identity. Borrowing the old `garden_slam` binding rejects
- Reject rectangle fallback, no owner, forged dictionary owner, preparing or
  merely ready owners, a genuinely unready candidate with an active owner,
  and a different active owner of another real ready same-map space
- Reject malformed first/middle/last members, outside/too-close/nonfinite or
  actual-contour body positions, overlap, invalid/insufficient capacity,
  wrong boss template, old boss identity, wrong boss group count, and replay
  after release
- Every plan verifies runtime, templates, validation state, global RNG, input
  entries/profile/player, geometry snapshot, cached routes, exact native body
  and shape handles, each body's space, and prepared-owner data are preserved
  The reusable query circle radius is scratch state, not collision authority
- Release all three candidate spaces, all bodies/shapes/query resources and
  prepared-owner references. Repeated cleanup is idempotent

## Retained failure and correction

Attempt01 completed all 51,605 checks with exactly three test failures and
exit 1. The newly installed physics space was already ready when inspected;
therefore the assertion that "no frames elapsed" meant unready was false, and
both ordinary/boss requests were correctly admitted by production. All other
checks, including the complete old branch and all 360 native positive groups,
passed. The exact script, log, exit code, input hashes, and result are retained.

Attempt02 changes only the test readiness setup: after installing the real
assembly, one actual body is detached from that candidate's physics space.
The per-piece readiness probe genuinely returns false, even with a typed
active owner. This intentionally incomplete candidate is rejected and freed.
The two positive candidates are separately installed unchanged and synchronized
normally. Native preservation checks also record each body's space RID.
No production behavior or readiness requirement was relaxed.

The second exact-fixture command was already running when narrower follow-up
rerun guidance arrived; it completed in about 25 seconds. It was the same
fixture only. No additional suite was run afterward. Both attempts are kept;
this is not represented as a first-attempt pass.

The prior v116 migration **575/0**, native entry **174/0**, and boss-only **9/0**
evidence is reused unchanged, not rerun. The final input manifest includes
its hashes. This camp result does not imply whole-project regression or merge
readiness.

## Reproduction

```sh
root=/tmp/godot-m1-v116-compat-camp-fresh
mkdir -p "$root"/{data,config,cache}
XDG_DATA_HOME="$root/data" \
XDG_CONFIG_HOME="$root/config" \
XDG_CACHE_HOME="$root/cache" \
GODOT_SILENCE_ROOT_WARNING=1 \
timeout 180 godot --headless --path . \
  --script res://tests/map_camp_admission_test.gd
```

`compat-camp-final-inputs.json` binds the 58-file source/resource set
(including the final script), final result, retained attempts, and reused evidence
to their SHA-256 hashes. The tested final sources were rehashed unchanged.
