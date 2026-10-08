# Focused presentation-clock preparation for the ranger study

Base and remote `main` checked on 2026-10-08:
`1602cbd055a58968a65c5851574d20173f715b50`.

The custom presentation previously set visual attack occupancy from its global
fps and attack frame count, or its idle count when attack art was absent. A
faster locomotion fps therefore shortened the existing half-second attack cue.
`ActorVisual` now keeps the original `6 / 12` second cue and maps an available
custom attack clip across that interval. Walk still samples the supplied global
fps. Catalog normalization and its direct frame-sampling contract are unchanged.
No actual attack, damage, cooldown, movement, collision or save code changed.

Godot 4.6.3, Linux, fresh isolated `/tmp` XDG directories:

| Check | Result |
| --- | --- |
| Initial editor import | Exit 0 |
| `presentation_swap_pose_test.gd` | 14 checks, 0 failures, exit 0 |
| `actor_sprite_depth_test.gd` | 329 checks, 0 failures, exit 0 |
| `presentation_adapter_main_test.gd` | 27 checks, 0 failures, exit 0; one map, zero combat ticks |
| `git diff --check` | Passed |

The new regression uses synthetic repeated existing static regions at 32 fps:
it checks the half-second countdown, middle attack frame at a quarter second,
return to walking, and the same duration without attack art. It does not certify
new ranger images. The existing Main fixture verifies actor identity, selected
bounds/contact shadow, projection, culling, clear, and exact preservation of
authoritative state and save bytes during presentation operations.

## Asset blocker and unverified boundaries

The intended source is `ranger-locomotion-preview.zip`, expected SHA256
`31a0e0e38260f279e8fb01b05fff468e8e3e386aa980cc192110823cdefb0dce`.
The source assets have not been integrated or inspected in this checkout, and
their content hash has not been verified here.

The independent single-direction ranger preview is therefore still pending.
The supplied 80% Walk / 20% Jog, 0.743682-second cycle, 16 right-facing frames,
128x192 source cells, 64x96 projected display, foot [64,158], world scale
`1 / (2 * 0.65)`, movement 240 world units/second and projected speed 156 px/second
are integration requirements, not verified results here. New ranger movement,
contact shadow and rendered contour acceptance have not been checked. No new
eight-direction, Idle or Attack art is claimed. Full suites, long-duration
checks, Windows exports and packaging were not run.
