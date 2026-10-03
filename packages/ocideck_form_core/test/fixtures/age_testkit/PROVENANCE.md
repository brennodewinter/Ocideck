# age test vectors (C2SP CCTV)

The complete `age/testdata` corpus of the Community Cryptography Test Vectors, byte for
byte as published — `git sparse-checkout set age/testdata` at the pinned commit:

- Upstream: https://github.com/C2SP/CCTV (`age/testdata`)
- Pinned commit: `1e3d2860d46e94e777e1b17c7a6f2436387e3ecc` (2026-06-05)
- Vectors: 143
- Licence: the upstream README says the vectors may be copied into a project "without
  attribution"; the C2SP project publishes its test vectors as CC0-1.0, and FORM_INTAKE.md
  D5 treats shared test vectors as CC0.

The copy was compared file by file with the one `dartage` 0.3.0 vendors (no difference).
Do not edit a vector; to refresh, repeat the sparse checkout at a newer commit and update the
pin here and in `test/form_seal_vectors_test.dart`.

`test/form_seal_vectors_test.dart` runs them through `openAge`. Vectors for features this
engine does not implement — passphrases, armor, hybrid and tag recipients — are skipped as
the corpus README allows, but every vector whose `expect` is not `success` must be refused
whatever its kind (a refusal is never skipped).
