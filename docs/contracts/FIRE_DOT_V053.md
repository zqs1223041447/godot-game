# Fire damage-over-time passive specialization

Base: published v0.52 commit `0abadf05c94545fb7585f5a7565cd7a8930c26cd`. This checkpoint contains implementation and successful first import; focused acceptance is pending.

Only the exact source line `+X% to Fire Damage over Time Multiplier` is added. Its additive stat is `fire_dot_multiplier_add`; a ten-percentage-point source contributes0.10. The eight ordinary nodes are4713(4%),5916(6%),13559(5%),31462(5%),54396(4%),2550(10%),11924(10%),29049(12%). All other lines on these nodes already execute. Node identities, class starts and graph edges remain unchanged; an unsupported additional line still prevents allocating the whole node.

Published reachability evidence places three entries on the blocked frontier for all seven starts:10221→54396→2550,7444→4713→5916→29049 and61804→13559→31462→11924. Opening these branches can also make the already-supported1550 reachable; that node gains no new effect. Legal schema31 builds could not allocate the eight incomplete nodes, so migration does not automatically grant a new multiplier to old allocations.

The cast snapshot includes optional `fire_dot_multiplier` only when the stat is nonzero; invalid input is retained long enough for strict compiler rejection. The initial cast freezes that sum. Both compiler preview and actual player burn use the same `BurnRules.raw_fire_dps` expression: existing resolved pre-defense fire × policy rate, then exactly once ×(1+sum). Zero uses the previous floating-point expression without a multiply-by-one. Preview `burn_profile.fire_dot_multiplier` carries the additive fraction and its existing role DPS/total already include the benefit.

Primary hits, duration, existing upstream modifiers, critical behavior, enemy burns, shock and non-fire hit components are unchanged. Ordinary ignite and direct ember generation use the factor; transferred ember inherits the existing resolved DPS and original absolute expiry without applying it again. No scheduler rewrite, new auxiliary gem, equipment family, loot pool or currency is included.

Schema32 freezes all source execution through31, validates a complete old31 envelope before migration and preserves its original bytes. Only the schema number changes; no point grant, identity remap, new allocation, inventory/reward/revision change occurs. Historical migration stages keep their frozen output validation.
