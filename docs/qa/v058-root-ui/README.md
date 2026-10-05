# Mana-before-life presentation

Primary developer, 2026-10-05. Reviewed the whole Chinese source-text family (40%, 10%, 8%) and the Mind Over Matter name, keeping all English keys/IDs untouched. The generator has explicit whole-line overrides; regeneration changes only these three effect strings and node 34098's Chinese name to 心灵升华. Unsupported mixed nodes retain their actual allocation gates.

The character sheet adds a percentage row within its existing scrolling grid, reading `get_mana_guard_profile().fraction`. Tooltip states shield absorption first, shared hit/burn coverage, mana-shortfall routing to life and the shared casting resource. No damage calculation occurs in UI. Storm Patrol's stale no-shock wording now reflects the existing one-second 15% shock attack.

Nine focused headless checks passed with exit 0 and no ERROR output (`presentation.log`, Godot 4.6.3): mock authoritative profile 0→40→0 update, resource-order wording, reviewed name/effect translations and Storm Patrol text. The mock checks display behavior only; real allocation/combat integration is owned by the main test batch. Initial fixture alias `Panel` shadowed a native class; renamed only that alias and reran the affected test, preserving the initial log. No layout redesign, new artwork or repeated screenshot gate; no native Windows acceptance claimed.
