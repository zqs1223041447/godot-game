# v74 source movement binding: implementation stage

Baseline a1dd1acf. This stage adds only source_gale_stride, resolving source node 63417 stat index 1 through the current player source parser. The existing 23 legacy bundles, old gale_stride ID/aliases, ordinary_roll and default CampState.begin stay available. Current Main ordinary spawning and camp preparation explicitly choose the new sampler, replacing one pool position without new random calls.

New monster speed uses the authored species/wave/flat base times one plus the source additive movement increase. Existing live actors retain their generation snapshot. The compact source cache includes actual source metadata, line and execution policy; failures clear the valid cache and never return the old flat value. No other node clauses, player allocation or resource mechanisms are granted.

The first shared editor import completed in 13.312 seconds, exit 0, with no ERROR lines. Focused source and real integration tests are in progress; this stage is an implementation backup, not completed acceptance. Save schema47, equipment46 and source45 remain unchanged. No Windows export, package, tag or Release.
