# Same-PCK comparison fixture correction

The first25-check package probe passed24 checks. Its migration comparison alone failed: the expected document originated from JSON (numeric values are floats), then expected.version was assigned integer35, while the actual model was reloaded through JSON and held float35. Strict typed recursive equality correctly rejected this mixed in-memory fixture.

Both documents now cross the same JSON reload boundary before strict comparison. Exact original schema34 backup bytes remain separately checked. No game script, resource, EXE or PCK changed. The complete first log/report and a three-check isolated numeric-type diagnostic are retained. Only this package probe is rerun;300-frame startup had not run before the failed probe.
