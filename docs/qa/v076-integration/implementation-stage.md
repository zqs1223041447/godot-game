# v76 independent monster supply and source shield percentages

Baseline76c9cab. Current v3 remaps only the last two ordinary-pool identities; legacy, stride-v1 and damage-life-v2 samplers remain explicit. Fixed special templates and descendants are unchanged.

The shared source adapter admits capacity58218:0 (8%) and atomic recovery21929:1 (4%capacity) plus6949:1 (10%recharge). No flat resource amount belongs to the source adapter. SourceShieldBudget separately supplies original monster bases: capacity3.12 ES; recovery1.56 ES and0.4225 recharge/second. Source increases add before one multiplier. Cache at most five complete source definitions, with both recovery entries in its key.

Factory results: capacity3.3696/nocharge; recovery1.6224/.46475 persecond; both5.2416/.46475. Existing4second damagedelay and resource time stages remain. Frozen source_shield_profile captures authored supply, legacybases, combinedbases andcapacity multiplier. New identities cannot omit this profile. Snapshot validation checks consumed scalar/provenance consistency without re-querying source definitions.

Map shield M=.20canonicalHP is a new base amount for these actors only. EncounterCompiler appends M times the frozen multiplier to current/maxshield; factory shield is not multiplied again. Missing shield remains missing, Strong's map HP multiplier does not change M. Actors without new shield identity/profile use their exact old map addition. Historical EncounterCatalog metadata remains unchanged; current conditional explanation belongs in F8.

First shared import14.272s, exit0, noERROR. Sourceadapter381checks passed; real factory/map/Main lifecycle validation is in progress. Stage backup only, not final acceptance. Schema47/gear46/source45 unchanged. No UI/art/package/tag/Release.
