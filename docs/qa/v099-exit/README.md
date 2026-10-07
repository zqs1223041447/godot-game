# Safe map completion before exit

Baseline: `d7e4121ddff09624de796f7857520926bd610d4e`.

The former pause-menu exit saved the current build without retrying a failed
map-completion transaction. After a transient write failure this could persist
the old active run, which startup would then abandon without its earned map
reward or tier completion. Window close also ignored the save result.

Both exit routes now call `Main.request_safe_exit()`: retry pending completion,
save current progress, and request quit only after both succeed. Each existing
save transaction retains its own atomic commit. If completion succeeds but the
following progress save fails, its already-persisted receipt remains completed;
retrying exit cannot award it again. A busy or repeated exit cannot nest writes
or request quit twice. Ordinary autosave/manual `save_build()` remains unchanged.

Main disables automatic window-close acceptance while it owns the scene and
restores the previous setting when removed. This permits a save failure to keep
the session open. Forced process termination or an OS crash is outside this fix.
The pause/death buttons use the same “保存并退出” label and display the returned
failure reason. No new discard-progress exit is added.

Validation in progress: one shared resource import completed without errors;
the root HUD route/text checks passed 7/7 after isolated-data/import setup was
corrected. The two earlier setup failures are preserved under
`../v099-root-ui/`. Actual Main/model fault-injection results will be recorded
here before integration. Newly added strings use existing bundled glyphs.

No save schema, balance, map generation, combat, font, or large reference-catalog
changes are needed. No package or release was created.
