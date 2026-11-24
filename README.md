# SIR keystream generator

SIR is a keystream generator for small hardware. Its 128-bit state has two
halves: a 64-bit nonlinear primary register and a 64-bit auxiliary LFSR. In
every round, each primary bit is updated in parallel by the same 4-input
Boolean function, RULEA, which reads a fixed sparse set of neighbouring bits.
The LFSR adds 8 round-key bits to the primary register each round, and one
keystream bit is produced per round.

This repository holds the Verilog RTL, testbenches, Python and C reference
models, and known-answer test vectors for the design published in the paper
cited below.

## Parameters

| Item | Value |
|---|---|
| State | 128 bits: 64-bit primary register P + 64-bit auxiliary LFSR L |
| Key / IV | 128 bits / 64 bits |
| Initialisation | P = K0 ^ IV, L = K1 ^ RotL1(IV) ^ 0x9E3779B97F4A7C15 (K = K0 \|\| K1) |
| Warm-up | 32 rounds, no output |
| Primary update | P'[i] = RULEA(P[i], P[i-1], P[i+1], P[i+16]) ^ P[i+12], indices mod 64 |
| Neighbourhood offsets | -1, +1, +16 |
| Coupling offset | +12 |
| RULEA | 1 ^ x2 ^ x0x2 ^ x1x2 ^ x1x3 ^ x0x2x3 |
| LFSR feedback taps | L[0], L[1], L[3], L[4] |
| Round key | L[0], L[8], ..., L[56] (after the LFSR step), XORed into P[0..7] |
| Output bit | RULEA(P[0], P[13], P[29], P[46]) ^ parity of the other 60 bits of P |
| Output taps | {0, 13, 29, 46} |

Bit 0 is the first bit of the key and IV bytes, so the most significant
bit of `key[0]`. Keystream bits are packed into bytes with the first bit in
the MSB.

## Repository layout

```
rtl/   sir_core.v           keystream core, one bit per clock after warm-up
       sir_xor_wrapper.v    byte-stream XOR wrapper around the core
tb/    tb_sir_core.v        checks the core against the KAT file
       tb_sir_xor_wrapper.v encrypts and decrypts the KAT plaintexts
model/ sir.py               Python reference model
       sir.c                C reference model
       gen_kat.py           regenerates kat/ from sir.py
       check_models.py      compares sir.py, sir.c and kat/
kat/   sir_kat.txt          test vectors, readable
       sir_kat.csv          same vectors, CSV
       sir_kat.mem          same vectors, one byte per line, read by the testbenches
Makefile
```

## Running

You need Python 3, a C compiler, and Icarus Verilog (`iverilog`, `vvp`).
Run everything from the repository root.

```
make            # model check and both simulations
make check      # Python vs C vs kat/ (8 vectors + 1000 random key/IV pairs)
make sim        # both testbenches
make kat        # regenerate kat/ from model/sir.py
make clean
```

Each testbench prints a match count and `OVERALL RESULT: PASS` or `FAIL`.

Without make:

```
mkdir -p build
iverilog -g2005 -o build/tb_sir_core.vvp rtl/sir_core.v tb/tb_sir_core.v
vvp build/tb_sir_core.vvp

iverilog -g2005 -o build/tb_sir_xor_wrapper.vvp \
    rtl/sir_core.v rtl/sir_xor_wrapper.v tb/tb_sir_xor_wrapper.v
vvp build/tb_sir_xor_wrapper.vvp
```

Reference models:

```
python3 model/sir.py 000102030405060708090a0b0c0d0e0f 0001020304050607 32

cc -O2 -o build/sir model/sir.c
./build/sir 000102030405060708090a0b0c0d0e0f 0001020304050607 32
./build/sir -b <key> <iv> <nbytes> > stream.bin    # raw bytes
```

Both print the keystream in hex. For this key and IV the first 16 bytes are
`4fde30b24fdf8ee4e83c23f60497d4c4`.

The core outputs a keystream byte every 8 clocks and has no way to pause.
The XOR wrapper pairs each input byte with the next keystream byte, so input
bytes must arrive at least once every 8 clocks. If an input byte is late, a
keystream byte is lost and every later output is wrong. The wrapper then sets
its `ks_dropped` output high, and it stays high until reset. Outputs produced
while `ks_dropped` is low are correct. The wrapper testbench checks this with
back-to-back input, one byte every 8 clocks, and random gaps of 0 to 40
clocks.

## Results

Hardware cost, diffusion and statistical test results are in the paper.

## Citation

W. A. Susantha Wijesinghe, "SIR: A sparse-interaction-based keystream
generator for lightweight hardware applications," *J. King Saud Univ.
Comput. Inf. Sci.*, vol. 38, art. 1063, 2026, doi:10.1007/s44443-026-01467-y

See `CITATION.cff` for a machine-readable entry.

## Note

SIR is a research design. No third-party cryptanalysis has reviewed it, so
do not use it in production.

## Author

- Prof. W.A. Susantha Wijesinghe
- Email: susantha@wyb.ac.lk
- Website: susanthawijesinghe.com

Licensed under the MIT License (see `LICENSE`).
