# Frozen chaos-defense dependency

`damage_resolver.gd` is the exact file from commit `897dbfc16c1308b2b6916fa9ba52792d9d82c293`, with only `class_name DamageResolver\n` removed to avoid a global name collision. Restoring that line must yield SHA256 `720dc69a7446334e8aec3ac15bdf7c1717fa7b96db5657e0c9622513121a4e23`; the existing chaos rules test asserts this before loading its oracle.

The historical defense text remains untouched. Its in-memory preload is redirected to this frozen dependency. The transitive live HitPenetration dependency is still separately guarded by its original hash. No comparison assertions were dropped or historical expectations relaxed.

The old test incorrectly required the production DamageResolver to stay frozen forever. Production added legitimate `excluded_tags` handling in `47f31d0`; before/after hashes and the completed regression are recorded in `docs/qa/purity-of-flesh-reference`.
