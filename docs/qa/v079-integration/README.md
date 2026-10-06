# Two passive name corrections

The runtime dictionary and generator change only IDs 8833 and 56716 to 冰霜之心 and 雷霆之心. Original English names, all other dictionary fields, gameplay code, version 0.78 and schema 48 remain unchanged.

The original executor was replaced before its first import returned. That result is unknown and is not counted as a pass. A fresh anonymous clone of main 2e25e471 restored the source. The first four changed source/test files were backed up in commit 40c6ec9; remaining files and hashes were retained locally during transport recovery.

The recovered project import exited 0 without ERROR. The actual passive panel search test passed 109 checks with exit 0. Chinese, English and ID searches use real text_submitted signals; model, save, revision and RNG observations remain unchanged. Detailed scope and original output are in ../v079-search/.

F8 caches change only the two names and their dependent HTML fingerprint. The deterministic HTML check passed. No full dictionary generation, Godot catalog export, battle suite, native screenshot, package or schema change was performed.

The connector catalog upload ended with HTTP 400: its base64 JSON request was 20,347,076 bytes, exceeding 16 MiB. UTF-8 JSON would also exceed the limit. No catalog blob SHA was returned. After official CLI authentication was restored, the final delivery was prepared for normal Git transport with the connector commit retained as its parent. Remote ref verification is recorded separately after push.
