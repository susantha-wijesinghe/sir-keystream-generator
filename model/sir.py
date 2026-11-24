#!/usr/bin/env python3
#
# sir.py
# Python reference model of the SIR keystream generator.
#
# Author      : Prof. W.A. Susantha Wijesinghe
# Email       : susantha@wyb.ac.lk
# Website     : susanthawijesinghe.com
# Date        : 24/11/2026
#
# Copyright   : © 2026  W.A. Susantha Wijesinghe
# License     : MIT (see LICENSE)
#
"""SIR keystream generator, bit-level reference model.

State is held as two lists of 64 bits, P (nonlinear primary state) and
L (auxiliary LFSR). Index 0 is the most significant bit of the 64-bit
value, so P[0] is the first bit loaded from the key/IV bytes.

Usage as a script:
    python3 sir.py <key_hex32> <iv_hex16> [nbytes]
prints nbytes (default 32) of keystream in hex.
"""

import sys
from typing import List, Sequence, Tuple

N = 64                          # width of P and of L
WARMUP_ROUNDS = 32
OFFSETS = (-1, 1, 16)           # neighbourhood of RULEA: P[i-1], P[i+1], P[i+16]
COUPLING = 12                   # extra XOR term P[i+12]
TAPS = (0, 13, 29, 46)          # RULEA inputs of the output function
LFSR_TAPS = (0, 1, 3, 4)        # feedback taps of L
INJECT_POSITIONS = range(8)     # round key is XORed into P[0..7]
INIT_CONSTANT = 0x9E3779B97F4A7C15


def int_to_bits(value: int, width: int) -> List[int]:
    return [(value >> (width - 1 - i)) & 1 for i in range(width)]


def bits_to_int(bits: Sequence[int]) -> int:
    value = 0
    for b in bits:
        value = (value << 1) | b
    return value


def bytes_to_bits(data: bytes) -> List[int]:
    return [(byte >> s) & 1 for byte in data for s in range(7, -1, -1)]


def bits_to_bytes(bits: Sequence[int]) -> bytes:
    if len(bits) % 8:
        raise ValueError("bit length must be a multiple of 8")
    return bytes(bits_to_int(bits[i:i + 8]) for i in range(0, len(bits), 8))


def rule_a(x0: int, x1: int, x2: int, x3: int) -> int:
    """RULEA = 1 ^ x2 ^ x0x2 ^ x1x2 ^ x1x3 ^ x0x2x3."""
    return 1 ^ x2 ^ (x0 & x2) ^ (x1 & x2) ^ (x1 & x3) ^ (x0 & x2 & x3)


class SIR:
    """One SIR instance, initialised with a 16-byte key and an 8-byte IV."""

    def __init__(self, key: bytes, iv: bytes):
        if len(key) != 16:
            raise ValueError("key must be 16 bytes")
        if len(iv) != 8:
            raise ValueError("iv must be 8 bytes")

        # P = K0 ^ V,  L = K1 ^ RotL1(V) ^ C   (K = K0 || K1)
        k = bytes_to_bits(key)
        v = bytes_to_bits(iv)
        v_rot1 = v[1:] + v[:1]
        c = int_to_bits(INIT_CONSTANT, N)
        self.P = [a ^ b for a, b in zip(k[:N], v)]
        self.L = [a ^ b ^ d for a, b, d in zip(k[N:], v_rot1, c)]

        for _ in range(WARMUP_ROUNDS):
            self.round()

    def round(self) -> int:
        """Run one round and return its output bit."""
        P, L = self.P, self.L
        a, b, c = OFFSETS

        # Primary update: P'[i] = RULEA(P[i], P[i-1], P[i+1], P[i+16]) ^ P[i+12]
        Pn = [
            rule_a(P[i], P[(i + a) % N], P[(i + b) % N], P[(i + c) % N])
            ^ P[(i + COUPLING) % N]
            for i in range(N)
        ]

        # LFSR step: shift left by one, feedback into the last position.
        fb = 0
        for t in LFSR_TAPS:
            fb ^= L[t]
        Ln = L[1:] + [fb]

        # Round key: 8 bits of the new L at stride 8, XORed into P[0..7].
        stride = N // len(INJECT_POSITIONS)
        for k, pos in enumerate(INJECT_POSITIONS):
            Pn[pos] ^= Ln[k * stride]

        # Output: RULEA on the four taps, XOR parity of the other 60 bits.
        z = rule_a(*(Pn[t] for t in TAPS))
        for i in range(N):
            if i not in TAPS:
                z ^= Pn[i]

        self.P, self.L = Pn, Ln
        return z

    def keystream_bits(self, nbits: int) -> List[int]:
        return [self.round() for _ in range(nbits)]

    def keystream(self, nbytes: int) -> bytes:
        """Keystream bytes, first bit in the MSB of each byte."""
        return bits_to_bytes(self.keystream_bits(8 * nbytes))

    def state(self) -> Tuple[int, int]:
        """Current (P, L) as 64-bit integers."""
        return bits_to_int(self.P), bits_to_int(self.L)

    def xor(self, data: bytes) -> bytes:
        """Encrypt or decrypt data with the next len(data) keystream bytes."""
        ks = self.keystream(len(data))
        return bytes(x ^ y for x, y in zip(data, ks))


def main(argv: Sequence[str]) -> int:
    if len(argv) not in (3, 4):
        print(__doc__.strip().splitlines()[-2].strip(), file=sys.stderr)
        return 1
    key = bytes.fromhex(argv[1])
    iv = bytes.fromhex(argv[2])
    nbytes = int(argv[3]) if len(argv) == 4 else 32
    print(SIR(key, iv).keystream(nbytes).hex())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
