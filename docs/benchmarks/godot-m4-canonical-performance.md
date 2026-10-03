# Godot M4 canonical HUD performance check

- Baseline: `fe7c7b196fbf4700237aced18454714917fc9728`; after source: `bac56b5d958e481fc7a85df947a200b8f759670a`.
- Runtime: Godot 4.6.3 official, Linux headless, AMD EPYC 9V74, 5 logical processors reported by the container.
- Each scenario ran sequentially in its own Godot process with a fresh XDG user/config/cache directory. The probe took no rendering, pixel, or Windows FPS measurements.
- Combat used the real `start_density_demo()` 100-monster catalog fixture, seed `210021`, `auto_fire=false`, and a test-only 100-second player invulnerability window. No monster stats or damage values were changed.
- Each combat sample was 600 fixed ticks = 10 simulated seconds, not a 600-second soak. The full-state SHA covers enemies, projectiles, hit events, damage trace, RNG, cooldown ledger, and canonical model snapshot.

| Scenario | Real hits | Kills / survivors | Peak kills in one step | Kill-step CPU peak before → after (ms) | K cold open before → after (ms) | K hot reopen mean before → after (ms) | Full simulation SHA |
|---|---:|---:|---:|---:|---:|---:|---|
| Default | 80 | 41 / 59 | 13 | 8.411 → 6.041 | 218.215 → 98.640 | 118.751 → 2.825 | `84b45159b2d9faa68a4b39a94c140a612bf39dcaf1d8ad3f50622e8a56e7fe28` |
| 5 Frost | 44 | 9 / 91 | 4 | 8.994 → 6.590 | 218.342 → 93.776 | 111.505 → 2.553 | `c55277b7966b8c3baa83a3ed3e060c32ffe1aed53c2c45a4f047d513a3b21a98` |
| 5 Tornado | 221 | 83 / 17 | 9 | 9.749 → 8.346 | 207.751 → 100.965 | 110.831 → 2.853 | `95c29aeb6c5b0bebaef2db78d829fe06c13a2ff31b0dfd443439f164812f4633` |

The complete simulation SHA matched for all three scenarios. The K menu hot-reopen mean fell by 97.6% (118.751 → 2.825 ms), 97.7% (111.505 → 2.553 ms), 97.4% (110.831 → 2.853 ms).

The 5-award XP batch recorded five `changed` callbacks and one successful save in both runs. Flush times were 600.281 → 503.129 ms, 497.722 → 510.786 ms, 546.647 → 517.984 ms. This includes synchronous refreshes from hidden inventory/talent views; the task intentionally measured this cost without expanding the production patch. These single samples are descriptive, not a timing guarantee.

All probe gates reported zero correctness failures: 10 HUD warmup updates followed by 240 updates left the model and RNG unchanged and did not increase skill compile counts; blocked-menu manual processing kept elapsed time, draw counters, model, and RNG frozen. Headless draw counters are not pixel evidence.

Detailed per-scenario samples, recipes, final states, and hashes are in [the after JSON](godot-m4-canonical-performance-after.json); full pre-patch data is in [the baseline JSON](godot-m4-canonical-performance-baseline.json).
