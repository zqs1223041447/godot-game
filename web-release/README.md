# Accepted web build publication

The 106 binary chunks reconstruct the exact 55,327,439-byte accepted ZIP. Each chunk, the whole ZIP, and all ten extracted files are checked against manifest.json. ZIP duplicates, unknown entries, nested paths and symlinks are rejected. The deployment directory contains only those ten files plus an empty .nojekyll.

Run from the repository root:

    python3 web-release/rebuild.py release-output

The output directory must not already exist. Do not commit release-output. Publish these wrapper files and chunks only on dot/20261020-web-release; main and game source are unchanged.

The workflow has independent release and pages jobs. Release needs contents:write only; Pages needs contents:read, pages:write and id-token:write only. Checkout never persists credentials. No long-lived secret is required. Existing release assets are compared and never overwritten. Pages API failures are visible in logs; an existing non-workflow Pages configuration is not changed. Environment branch restrictions or insufficient Pages administration permissions may require owner configuration.

Official action commits verified on GitHub:
- https://github.com/actions/checkout/commit/11bd71901bbe5b1630ceea73d27597364c9af683
- https://github.com/actions/upload-artifact/commit/ea165f8d65b6e75b540449e92b4886f43607fa02
- https://github.com/actions/deploy-pages/commit/d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e

Pages upload is built directly as a tar artifact so there are no transitively unpinned composite actions. Official deployment conventions: https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages

Acceptance after deployment: verify the returned HTTPS URL, successful asset fetches and hashes, application/wasm MIME type, real-browser startup/movement/UI/audio, console errors, save/reload and second-tab exclusion. Previous actual browser acceptance is documented in docs/qa/status-hit-web-20261019/acceptance.json; the earlier export report's browser_tested=false predates that testing.
