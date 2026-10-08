# v126 default ranger: bounded game acceptance

Base main: `55793a0cec8c22413db4d1d4f367f58f31293d54`.
Source archive: `82ed58ba0a3ef7e8ee48e29b6b148c7576c3fc86`,
`art-studies/v126/`; its archived tree is unchanged. The source and runtime
PNG both have SHA-256
`1750ae246713f0e8af728b7c2cb473967ae3bc49c93ee099eabe8d0eebbd9700`.
Runtime metadata differs from the source only in `texture_path`, pointing to
the imported `res://assets/actors/ranger_v126.png`. The ignored research
directory is never used as a runtime resource. Mipmaps are enabled.

The original 256 unique rendered poses remain unchanged: eight directions,
10 Idle / 16 Walk / 6 Attack source poses per direction. The existing schema1
presentation contract references 45 logical frames per direction at 12fps:
Idle30 / Walk9 / Attack6. Cells are 160x224 with root `[80,174]`, projected
canvas 80x112 at the existing 0.65 camera. The independent contact shadow uses
world half size `[32,10]`. No source pose, scale, root or blend was adjusted.

Main selects the default through the existing `set_hero_presentation` after
the actor layer is cleared in `restart_run`. This covers first launch, map
entry, restart and town return. Only `scripts/main.gd` changes production
behavior. The old catalog hero and explicit `{}` selection remain available;
setting `DEFAULT_HERO_PRESENTATION_PATH` to an empty string is the code-only
rollback. Missing/invalid resources also leave the original catalog path.
There is no saved character option, new animation framework or monster change.

## Evidence

- Source archive hashes: all 19 listed files matched. Read-only atlas verifier:
  all 256 decoded RGBA regions matched their recorded pixel hashes; 360 region
  references, clips, root, scale, alpha margins and license records passed.
- `ranger_default_main_test.gd`: **233 headless checks, zero failures** and
  **252 native checks, zero failures**. Native includes 19 PNG captures.
  Every direction traverses all nine Walk references and stops into authored
  Idle; Idle loops, Attack reaches its explicit recovery endpoint, and cues
  leave game authority/RNG unchanged. Moving attack recovery resumes Walk.
  Original movement speed, fixed root and retained independent shadow pass.
  Motion-off holds directional Idle during movement/attack. Explicit legacy
  selection, restart, two lawful map entries and a town return pass.
- The same finite Main test exercises an unmodified owned basic attack through
  actual held mouse input: four admissions at the original 0.588235s cooldown,
  immediate retries rejected, recovery between admissions, and Idle after
  release. It checks presentation behavior rather than replacing combat rules.
- Existing presentation resource contract: 314 checks / zero failures; swap
  pose: 14 / zero; Main adapter: 28 / zero; Main actor depth: 13 / zero.
  The adapter explicitly clears the new default before its legacy swap probes
  and expects the configured Main default after town return, preserving its
  identity, culling, save, roster and authority comparisons.
- All eight movement directions and representative recovery poses were
  visually inspected in actual 1280x720 game captures, along with the source
  atlas. Hood/body/limbs remain readable; no obvious new cropping or missing
  body pieces appeared. Town stalls can naturally occlude the hero through
  shared depth ordering. Map walk/attack captures are included here.
- `git diff --check`: passed. Godot 4.6.3, Linux, native X11 OpenGL/Mesa
  llvmpipe. This is controlled finite presentation evidence, not natural
  long-run footage, hardware FPS or Windows acceptance.

Walk remains a 0.75s time-driven sparse sample, approximately 0.85% longer than
the east fitted source cycle. Depth/diagonal projection differs; perfect foot
locking is not claimed. The six Attack poses are the declared recovery-only
slice, ending at offline source f38; they do not define release or damage.
No long-duration run, full repository regression, Windows export or packaging
was performed. The initial broad editor import encountered the two existing
corrupt QA images under v116/v118; the v126 asset import and mipmap reimport
passed. Unavailable native audio was bypassed with the dummy audio driver.

## Reproduce the focused check

Import the project normally once, then from the repository root:

```sh
test_runtime=$(mktemp -d /tmp/godot-ranger-v126-check-XXXXXX)
mkdir -p "$test_runtime/data" "$test_runtime/config" "$test_runtime/cache"
XDG_DATA_HOME="$test_runtime/data" XDG_CONFIG_HOME="$test_runtime/config" \
XDG_CACHE_HOME="$test_runtime/cache" godot --headless --path . \
  --script res://tests/ranger_default_main_test.gd -- --report=/tmp/ranger-result.json
```

For native capture, omit `--headless`, use `--audio-driver Dummy` when needed,
and append `--capture-dir=/tmp/ranger-native-frames` after `--`.
`tools/prepare_ranger_default.py` reproducibly copies the verified original PNG
and remaps only the metadata path; it does not rerender or alter pixels.
