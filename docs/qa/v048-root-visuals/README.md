# Sunwell visual layer

Primary-developer changes, 2026-10-05.

- The new spring_basin geometry style uses warmer sandstone paving and still
  muted-green water in raised stone basins. All opaque basin parts stay within
  the collision rectangles supplied by world_geometry; no extra blocked route
  is suggested by oversized props. The old garden and ruins branches remain.
- sunwell_echo telegraphs keep the exact authoritative center and radius.
  Both windups retain a boundary even at minimum effects. Small single/double
  strokes distinguish the current pulse, without a second fictitious hit circle.
- The renderer consumes the current-pulse elapsed time from the read-only state.
  Recovery has no danger-boundary or pulse cue. No clock, state or RNG is changed.
- Focused presentation test: 34 checks, 0 failures, process exit 0, no ERROR.
  See presentation.log. Checks cover footprint containment, both windups,
  minimum/high effects, primitive budget, recovery/expiry, immutable input and RNG.
- Initial test harness parse failed because the alias Environment collided with
  Godot's native class name. Renamed the test alias to EnvironmentArt; no production
  renderer changes were needed. The failed launch is not counted as a pass.
- This is a focused data/render-command test, not a Windows hardware performance
  or completed native visual inspection.

## One native map review

At 2026-10-05 09:29–09:31 UTC the primary developer opened the real main scene
in an isolated test profile, entered sunwell_terrace through the actual map
commands and paused simulation for layout review. At 1180×812 the four stone
basins, cross passage, exterior paths, camp markers and lower entrance were
visible with no oversized prop covering the routes. This did not exercise combat,
mouse interactions or Windows frame rate; no persistent PNG is claimed.
The Linux desktop lacked an audio device and fell back to the dummy driver;
this environment warning did not prevent the map rendering. The game was then
closed and absence of the window was confirmed.

The review exposed a pre-existing fixed HUD subtitle showing the old garden
name. It now reads the current map/town caption on world-context refresh.
A separate focused caption check passed 5 checks, 0 failures, exit 0. The
static map review was not repeated merely for this text-only fix.
