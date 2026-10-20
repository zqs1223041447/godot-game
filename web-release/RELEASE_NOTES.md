# Browser build 2026-10-20

This ZIP is the previously accepted browser build associated with game source commit 065913e817d90fcd2bc3a707137da66af2bfbc2e. The release tag points to the publication wrapper commit, not to a newly exported game.

SHA256: fb985fc96696d1dd026a2306b30828c1a1e2871995f9982916fa8df67f28dbf7

Actual Firefox/WebGL2 testing observed the documented status/hit visual subset. See the source repository's docs/qa/status-hit-web-20261019/acceptance.json for evidence and explicit limitations. This is not a claim of exhaustive browser, device, timing or performance coverage.

Extract the ZIP into a static HTTPS site, or serve on localhost. Opening index.html directly as a file is unsupported. The build requires WebGL2, WebAssembly and Web Locks; it is single-threaded and requires no cross-origin isolation headers. Progress is browser-local. Allow background saving to finish before closing; private browsing or clearing site data can lose progress.

GitHub Pages is deployed by a separate job. A downloadable release does not prove that Pages was enabled or that its public URL passed a post-deployment smoke test. Check the workflow's Pages result before advertising a playable address.
