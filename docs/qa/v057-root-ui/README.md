# Consolidated Chinese passive-tree visual review

Primary developer, 2026-10-05 18:41–18:44 UTC. One native Linux cloud session using actual main scene, isolated XDG save directories, 1180x812 game window on 1364x1024 desktop. This is not a Windows hardware/FPS test.

Observed via native computer-use tools:
- Opened the actual T passive screen from town. Chinese class/partition labels and terminology explanation rendered without visible missing-glyph boxes in reviewed samples.
- Searched node 11239: the multi-line Wind Dancer description displayed Chinese conditions and extra increase/decrease wording, ending in the unsupported suffix; long text wrapped within the right detail panel.
- Searched implemented node 54396: Fire DoT multiplier +4% displayed without an unsupported suffix.
- Opened the Chinese partition menu and selected Assassin. The rendered graph actually changed to its separate small subtree with its browsing-only context.
- Clicked the start button to return to the standard tree; searched English alias `wind dancer`, which resolved to Chinese node 11239.
- Closed the game window after the consolidated review. No repeated per-node screenshot gate was introduced. Screenshots were observed through the tool, not saved as PNG artifacts.

Root fixed the existing dirty-flag omission in `_change_partition` and `_focus_start`, so these actions rebuild the selected graph rather than returning early from cached refresh. The no-match feedback now says 编号 rather than ID. The main integration batch verifies actual graph sets and state immutability.

Native startup log is `../v057-root-native.log`. The cloud machine has no audio output device; ALSA failed and Godot explicitly used its dummy audio driver. The game reached playable-arena-ready; this environment warning is not presented as an all-error-free native run. Full glyph coverage is separately verified by the font audit, not inferred from this sample view.
