# Initial comparison fixture mismatch

Both no-burn simulations completed with exit0, but full observations differed only in three startup rings created by restart before the deterministic seed and before replacing the initial actors. Original binary/save/logs/harness are preserved here. A read-only inspection confirmed byte equality after diagnostic-only removal of the rings field; that is diagnosis, not final acceptance.

The corrected fixture clears the discarded pre-seed actors’ rings/particles/text/pickups while building the controlled population. Final comparison includes the full rings field and uses no projections. Production code unchanged by this fixture correction. Initial timings are not improvement evidence.
