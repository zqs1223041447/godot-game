# Windows localhost launcher and startup diagnostics

Download godot-game-web-windows-launcher.zip, extract it completely, then run Start-Game.exe. It serves only the game's ten asset filenames at http://localhost:18764/ and opens the default browser. No Python, Node or Go installation is required. The executable is unsigned; do not disable security protection if it is blocked.

The original game assets are hash-verified against the previously accepted ZIP. Only index.html changes, adding a file-protocol preflight and more specific failure details. The user's earlier screenshot does not establish its underlying cause; this release does not claim that specific failure has been reproduced or resolved.

Publication is gated on Go tests on Linux and Windows, Windows native process smoke tests using --no-browser, exact HTTP asset checks, WASM MIME and fixed-port conflict behavior. These transport checks do not replace real-browser gameplay acceptance or establish audio/device/performance coverage.

Use the same localhost address and browser profile to retain access to browser-local saves. GitHub Pages is not enabled by this workflow. Existing release assets are not overwritten.

Windows server/process test success is not a claim of Windows browser or gameplay visual validation.
