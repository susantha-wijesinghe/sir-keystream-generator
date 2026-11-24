# Changelog

## v1.0.0

Matches the published design (doi:10.1007/s44443-026-01467-y).

Parameter changes from v0.9-preprint:

| Item | v0.9-preprint | v1.0.0 |
|---|---|---|
| Neighbourhood offsets | -1, +1, +8 | -1, +1, +16 |
| Coupling offset | +2 | +12 |
| Output taps | {0, 16, 32, 48} | {0, 13, 29, 46} |

Unchanged: RULEA, LFSR taps {0, 1, 3, 4}, 8-bit round-key injection into
P[0..7], initialisation constant, 32 warm-up rounds, 128-bit key, 64-bit IV.

Because of these changes, v1.0.0 keystreams differ from v0.9-preprint
keystreams for every key and IV.

Other changes:

- New test vectors in `kat/` (8 vectors, 64 bytes each), generated from the
  reference model.
- Testbenches read `kat/sir_kat.mem` and check every byte. The XOR wrapper
  testbench now instantiates the correct module (`sir_xor_wrapper`) and
  checks both encryption and decryption.
- Added a C reference model (`model/sir.c`) and a script that checks it
  against the Python model.
- Added a Makefile.
- Layout: `python/` is now `model/`, and `test_vectors/` is now `kat/`.

## v0.9-preprint

The first public version, made before publication with the original
parameters.
