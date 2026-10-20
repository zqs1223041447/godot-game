# Startup bundle publication

This directory reuses the existing web-release/chunks and its validated rebuild.py. Do not modify the old chunks, old published ZIP or old publication workflow. The new workflow runs only for startup-fix/** and .github/workflows/startup-fix.yml on dot/20261020-web-release.

Flow: verify original archive and ten files; replace only index.html using manifest.json; native Go tests/vet on Linux and Windows; build and process-smoke-test each native launcher with --no-browser; package the Windows binary with ten game assets and Chinese instructions; publish only after both matrix jobs pass. A Linux cross-build alone is not Windows execution evidence.

The smoke test checks exact localhost HTTP content, application/wasm, non-game file rejection and a second process exiting 1 on the occupied fixed port. It never launches a browser. Go unit tests cover the launcher handler and resource safeguards. Browser gameplay and the user's original screenshot diagnosis are separate acceptance scopes.

New release: web-playable-20261020-startup-fix. The old release is retained. Existing new-tag assets are compared, never overwritten. The executable is unsigned. No Pages operation or permission is requested.

Official actions pinned to commits verified on GitHub:
- https://github.com/actions/checkout/commit/11bd71901bbe5b1630ceea73d27597364c9af683
- https://github.com/actions/setup-go/commit/d35c59abb061a4a6fb18e82ac0862c26744d6ab5
- https://github.com/actions/upload-artifact/commit/ea165f8d65b6e75b540449e92b4886f43607fa02
- https://github.com/actions/download-artifact/commit/d3f86a106a0bac45b974a628896c90dbdf5c8093

The setup action selects official Go 1.27.3, matching the independently verified local toolchain, and records go version in its test logs. Go launcher source uses only the standard library. No credentials are stored; checkout persist-credentials is false. Only release has contents:write.

Successful Windows server/process testing is not Windows browser rendering or gameplay visual acceptance.

The game baseline is 065913e817d90fcd2bc3a707137da66af2bfbc2e, not a claim about current main. Startup shell changes are separately included under startup-fix/web with their Node tests under startup-fix/tests. CI executes those actual copied sources on Ubuntu.

Startup shell changes were committed as 3fa8d01018f3aaf097942aa3b79d8f323d8953c0. The PCK remains the 065913e8 game build; no game pack re-export occurred for this launcher bundle.
