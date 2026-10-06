# v074 source monster grant adapter

`source_gale_stride` admits only the current parsed stat at source node `63417`,
zero-based index `1`, currently `4% increased Movement Speed`. It neither applies
the sibling armour line nor allocates/executes the node's ascendancy tree.
The parser's native increased value is the only numeric authority.

`SourceMonsterGrants.resolve(id)` returns `{ok, reason, stats, definition}`.
`get_definition(id)` returns the detached definition or an empty dictionary.
Definitions include the exact source entry, source references, original line,
effective execution policy, current save version, and Chinese display name.
The runtime is lazy-loaded to avoid the existing registry/jewel preload cycle.

The one-entry static result cache is keyed by the compact source metadata,
node/index/original line, execution policy, and current save version. Only a
validated result is cached; any rejection clears it. The compact read-only
`SourceTreeData.stat_entry` accessor uses the existing loaded tree and copies
only eight scalar fields. No monster-resolution path loads/copies the tree.

The focused test covers current parser equality, precise single-entry admission,
explicit failures for unknown IDs/malformed provenance/multiple or unsupported
effects, finite nonnegative numeric validation, detached results, cache hits,
source metadata and line invalidation, policy/version key separation, and the
compact lookup boundary. Fixture mutations exist only in test code and restore
the preexisting source caches. There is no production provider-injection API.

After the parent performs the shared Godot import, run:

```sh
python3 docs/qa/v074-source-grants/run-focused.py
```

This checks the adapter and the existing SourceTreeData contract with isolated
Linux XDG directories. Each run records logs and hashes of the transitive input
files before/after execution. It does not import the project or run unrelated
history-wide tests.
