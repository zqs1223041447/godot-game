# Released six-craft equivalence

The same probe ran against the immutable v048 worktree at 57ed67b and the candidate. Both exited 0 without script errors. All 1,008 records and 3,024 rule/planner plan pairs serialize to exactly the same 6,621,672 bytes. Details and source hashes are in comparison.json; baseline.log and candidate.log retain original output. old-crafting.bin.gz is a deterministic compressed copy of the baseline byte oracle.

The probe covers 14 bases, levels 1/8/16/30, normal/magic/rare source instances, six original actions, and seeds 0/4927/-817. It records original action metadata, seed versions, quotes, pure plans, authoritative planner candidates, and global RNG nonconsumption. Invalid operations on a rarity are included as unchanged rejection results. This is one scoped old-path comparison, not the historical test suite.
