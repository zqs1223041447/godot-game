# Bounded burn allocation work

Baseline is the error-free clock repair d5ef658, not the earlier assertion/error timings. Stage one changes only BurnRuntime and main: scalar monster maximum clock (no copied/sorted public snapshot), cached identity-key order with detached public states, validated same-time advance_target returning a correctly typed empty result without copying unchanged state, and skipping scratch source-map entries for empty segments. Positive-width arithmetic, expiry and death handling remain unchanged.

The original code updates remaining and last_time only inside width>0. Zero-width calls retain exact original values; no extra floating normalization was introduced. Cache holds keys only and rebuilds on new key, successful removal, expiry erase or reset. Existing-key overwrites read the new state dictionary on every request. Public snapshots and nested provenance remain deep copies.

797 pure checks compare full returned bytes and internal semantic state against a frozen d5ef658 BurnRuntime (only class_name renamed). Coverage includes IDs2/10 and player ordering, overwrite/weaker applications, detached data mutation, capacity101, remove/reinsert/expiry/reset, per-target clocks, reversed/corrupt inputs, advance_all atomic failure and tiny-delta underflow, and equal-time precision at0/.1/1e6.

All four same-scene observations match the no-error baseline exactly, including actors, carriers, burn/damage/event traces, resources, canonical save state, deaths/rewards and RNG. Full metrics are in ../v050-density/allocation-comparison.json. The controlled ember upper-bound mean is1402.5→958.5ms with instrumentation; genuine death/transfer sample mean53.49→45.56ms, p95 184.83→159.10ms, max1127.73→830.73ms. These are cloud debug CPU samples, not Windows FPS. The upper-bound fixture repeatedly seeds180 carriers per tick to isolate heavy contact work; the death case seeds one such volley and lets real motion/split/expiry/27 root deaths proceed for150ticks.

The original failing assertion was observed in the debug engine. Godot release builds omit assert evaluation; no Windows crash was established: https://docs.godotengine.org/en/4.5/classes/class_%40gdscript.html#class-gdscript-method-assert


## Same-instant completion

The final main path asks for a fresh detached numeric-ID list only when every active monster has exactly the requested clock and positive remaining lifetime. It rebuilds the live-target map in each original causal loop, removes missing/dead bodies, and retains the original empty settlement plus deferred-death/transfer flush before exiting. It never memoizes a finished timestamp or exposes borrowed states. Nineteen additional checks cover fresh clocks, ID-list isolation, independently timed targets, replacement, missing/dead cleanup and pending one-hop transfer; the45 clock checks also pass on this final path.

Final timings use unwrapped production main/model/BurnRuntime classes, not timing subclasses. The before main comes from d5ef658 with only its BurnRuntime preload redirected to the class-renamed frozen baseline. Both scenarios retain byte-identical full observations and actual save files. High-contact mean1245.97→687.40ms (-44.8%), p95 1323.62→745.39, max1327.17→819.19. The150-tick death/propagation segment mean54.05→42.44ms (-21.5%), p95 199.80→145.05, max1008.31→735.61. All27 legal root rewards remain. Peak latency is still high; this does not solve all stalls.

These are controlled initial populations and carrier/burn setup followed by actual combat code, not recordings of natural map entry or WindowsFPS. Original invalid ERROR timings are never used for improvement percentages. No reward, UI, delayed settlement, population reduction or new architecture was added.
