#!/usr/bin/env python3

"""
===============================================================================
Title      : SIR Reference Model (Sparse-Interaction Keystream Generator)
File       : sir_reference_model.py
Author     : Dr. W. A. Susantha Wijesinghe
email      : susantha@wyb.ac.lk
Date       : 19-03-2026

Description:
------------
This file implements the Python reference model of the SIR keystream generator.

The model is used for:
    - Functional validation of the Verilog implementation
    - Generation of deterministic test vectors
    - Experimental evaluation of statistical and diffusion properties

Architecture:
-------------
The SIR construction consists of:
    - A nonlinear primary state updated via sparse local interaction
    - An auxiliary LFSR providing round-dependent perturbation

The update rule is applied uniformly across the state, enabling parallel
combinational mixing.

Notes:
------
- This is a research reference implementation (not optimized for speed)
- Used to generate test vectors for RTL verification
- See sir_generate_test_vectors.py for automated vector generation

===============================================================================
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Tuple


# ============================================================
# Parameters
# ============================================================

PRIMARY_BITS = 64
AUX_BITS = 64
KEY_BITS = 128
IV_BITS = 64
WARMUP_ROUNDS = 32
INIT_CONSTANT = 0x9E3779B97F4A7C15


# ============================================================
# Bit utility functions
# ============================================================

def int_to_bits(value: int, width: int) -> List[int]:
    """Convert integer to MSB-first bit list of given width."""
    if value < 0 or value >= (1 << width):
        raise ValueError(f"value out of range for width={width}")
    return [(value >> (width - 1 - i)) & 1 for i in range(width)]


def bits_to_int(bits: List[int]) -> int:
    """Convert MSB-first bit list to integer."""
    value = 0
    for b in bits:
        if b not in (0, 1):
            raise ValueError("bits must contain only 0/1")
        value = (value << 1) | b
    return value


def bytes_to_bits(data: bytes) -> List[int]:
    """Convert bytes to MSB-first bit list."""
    bits: List[int] = []
    for byte in data:
        for shift in range(7, -1, -1):
            bits.append((byte >> shift) & 1)
    return bits


def bits_to_bytes(bits: List[int]) -> bytes:
    """Convert MSB-first bit list to bytes."""
    if len(bits) % 8 != 0:
        raise ValueError("bit length must be a multiple of 8")
    out = bytearray()
    for i in range(0, len(bits), 8):
        byte = 0
        for b in bits[i:i + 8]:
            if b not in (0, 1):
                raise ValueError("bits must contain only 0/1")
            byte = (byte << 1) | b
        out.append(byte)
    return bytes(out)


def xor_bits(a: List[int], b: List[int]) -> List[int]:
    """Bitwise XOR of equal-length bit lists."""
    if len(a) != len(b):
        raise ValueError("bit lists must have the same length")
    return [x ^ y for x, y in zip(a, b)]


def rotl_bits(bits: List[int], shift: int) -> List[int]:
    """Rotate-left a bit list by shift positions."""
    n = len(bits)
    if n == 0:
        return []
    shift %= n
    return bits[shift:] + bits[:shift]


def xor_bytes(a: bytes, b: bytes) -> bytes:
    """Bytewise XOR of equal-length byte strings."""
    if len(a) != len(b):
        raise ValueError("byte strings must have equal length")
    return bytes(x ^ y for x, y in zip(a, b))


def hex_to_bytes_fixed(hex_str: str, expected_len_bytes: int) -> bytes:
    """Parse hex string into fixed-length bytes."""
    hs = hex_str.strip().lower()
    if hs.startswith("0x"):
        hs = hs[2:]
    if len(hs) != expected_len_bytes * 2:
        raise ValueError(
            f"hex string must be exactly {expected_len_bytes * 2} hex characters"
        )
    try:
        data = bytes.fromhex(hs)
    except ValueError as exc:
        raise ValueError("invalid hex string") from exc
    return data


def bytes_to_hex(data: bytes) -> str:
    """Convert bytes to lowercase hex string without 0x prefix."""
    return data.hex()


# ============================================================
# Core Boolean rule and state update
# ============================================================

def rule_a(x0: int, x1: int, x2: int, x3: int) -> int:
    """
    RuleA(x0, x1, x2, x3) =
        1 XOR x2 XOR x0x2 XOR x1x2 XOR x1x3 XOR x0x2x3
    """
    return 1 ^ x2 ^ (x0 & x2) ^ (x1 & x2) ^ (x1 & x3) ^ (x0 & x2 & x3)


def update_primary(P: List[int]) -> List[int]:
    """
    Revised primary-state update:
        P'_i = RuleA(P_i, P_{i-1}, P_{i+1}, P_{i+8}) XOR P_{i+2}
    Indices are modulo 64.
    """
    if len(P) != PRIMARY_BITS:
        raise ValueError("primary state must be 64 bits")

    Pn = [0] * PRIMARY_BITS
    for i in range(PRIMARY_BITS):
        x0 = P[i]
        x1 = P[(i - 1) % PRIMARY_BITS]
        x2 = P[(i + 1) % PRIMARY_BITS]
        x3 = P[(i + 8) % PRIMARY_BITS]
        Pn[i] = rule_a(x0, x1, x2, x3) ^ P[(i + 2) % PRIMARY_BITS]
    return Pn


def update_lfsr(L: List[int]) -> List[int]:
    """
    64-bit LFSR update:
        fb = L[0] XOR L[1] XOR L[3] XOR L[4]
        L' = (L1, L2, ..., L63, fb)
    """
    if len(L) != AUX_BITS:
        raise ValueError("auxiliary state must be 64 bits")

    fb = L[0] ^ L[1] ^ L[3] ^ L[4]
    return L[1:] + [fb]


def extract_round_key(L: List[int]) -> List[int]:
    """Extract 8-bit round-dependent injection vector from L."""
    if len(L) != AUX_BITS:
        raise ValueError("auxiliary state must be 64 bits")
    return [L[i] for i in range(0, 64, 8)]


def inject_round_key(P: List[int], rk: List[int]) -> List[int]:
    """Inject 8 bits contiguously into P[0..7]."""
    if len(P) != PRIMARY_BITS:
        raise ValueError("primary state must be 64 bits")
    if len(rk) != 8:
        raise ValueError("round key must be 8 bits")

    out = P[:]
    for i in range(8):
        out[i] ^= rk[i]
    return out


def output_bit(P: List[int]) -> int:
    """
    Revised nonlinear output:
        r = RuleA(P0, P16, P32, P48)
        z = r XOR parity(all other state bits)
    """
    if len(P) != PRIMARY_BITS:
        raise ValueError("primary state must be 64 bits")

    taps = {0, 16, 32, 48}
    r = rule_a(P[0], P[16], P[32], P[48])

    parity = 0
    for i in range(64):
        if i not in taps:
            parity ^= P[i]

    return r ^ parity


# ============================================================
# Cipher state and round function
# ============================================================

@dataclass
class SIRKeystreamState:
    P: List[int]
    L: List[int]

    def copy(self) -> "SIRKeystreamState":
        return SIRKeystreamState(self.P[:], self.L[:])


class SIRKeystream:
    """Golden reference model."""

    def __init__(self, key: bytes, iv: bytes):
        if len(key) != KEY_BITS // 8:
            raise ValueError("key must be 16 bytes (128 bits)")
        if len(iv) != IV_BITS // 8:
            raise ValueError("iv must be 8 bytes (64 bits)")

        self.key = key
        self.iv = iv
        self.state = self._initialize_state(key, iv)
        self._warmup(WARMUP_ROUNDS)

    @staticmethod
    def _initialize_state(key: bytes, iv: bytes) -> SIRKeystreamState:
        """
        Initialization:
            K = K0 || K1
            P0 = K0 XOR V
            L0 = K1 XOR RotL1(V) XOR C
        """
        key_bits = bytes_to_bits(key)
        iv_bits = bytes_to_bits(iv)

        if len(key_bits) != 128 or len(iv_bits) != 64:
            raise ValueError("unexpected key/iv bit lengths")

        K0 = key_bits[:64]
        K1 = key_bits[64:]
        V = iv_bits[:]
        V_rot1 = rotl_bits(V, 1)
        C_bits = int_to_bits(INIT_CONSTANT, 64)

        P0 = xor_bits(K0, V)
        L0 = xor_bits(xor_bits(K1, V_rot1), C_bits)

        return SIRKeystreamState(P0, L0)

    def _round(self) -> int:
        """Execute one cipher round and return one keystream bit."""
        Pn = update_primary(self.state.P)
        Ln = update_lfsr(self.state.L)
        rk = extract_round_key(Ln)
        Pn = inject_round_key(Pn, rk)
        z = output_bit(Pn)

        self.state.P = Pn
        self.state.L = Ln
        return z

    def _warmup(self, rounds: int) -> None:
        """Discard output for the given number of rounds."""
        for _ in range(rounds):
            _ = self._round()

    def keystream_bits(self, nbits: int) -> List[int]:
        """Generate nbits keystream bits."""
        if nbits < 0:
            raise ValueError("nbits must be nonnegative")
        return [self._round() for _ in range(nbits)]

    def keystream_bytes(self, nbytes: int) -> bytes:
        """Generate nbytes keystream bytes."""
        if nbytes < 0:
            raise ValueError("nbytes must be nonnegative")
        bits = self.keystream_bits(nbytes * 8)
        return bits_to_bytes(bits)

    def encrypt(self, plaintext: bytes) -> bytes:
        """Encrypt plaintext by XORing with generated keystream bytes."""
        ks = self.keystream_bytes(len(plaintext))
        return xor_bytes(plaintext, ks)

    def decrypt(self, ciphertext: bytes) -> bytes:
        """Decrypt ciphertext by XORing with generated keystream bytes."""
        ks = self.keystream_bytes(len(ciphertext))
        return xor_bytes(ciphertext, ks)

    def state_as_hex(self) -> Tuple[str, str]:
        """Return current internal states as hex strings."""
        p_hex = f"{bits_to_int(self.state.P):016x}"
        l_hex = f"{bits_to_int(self.state.L):016x}"
        return p_hex, l_hex


# ============================================================
# Convenience API
# ============================================================

def sir_keystream(key: bytes, iv: bytes, nbytes: int) -> bytes:
    """Generate keystream bytes from key and iv."""
    cipher = SIRKeystream(key, iv)
    return cipher.keystream_bytes(nbytes)


def sir_encrypt(key: bytes, iv: bytes, plaintext: bytes) -> bytes:
    """Encrypt plaintext with SIR."""
    cipher = SIRKeystream(key, iv)
    return cipher.encrypt(plaintext)


def sir_decrypt(key: bytes, iv: bytes, ciphertext: bytes) -> bytes:
    """Decrypt ciphertext with SIR."""
    cipher = SIRKeystream(key, iv)
    return cipher.decrypt(ciphertext)


def sir_keystream_hex(key_hex: str, iv_hex: str, nbytes: int) -> str:
    """Generate keystream bytes and return as hex string."""
    key = hex_to_bytes_fixed(key_hex, 16)
    iv = hex_to_bytes_fixed(iv_hex, 8)
    return bytes_to_hex(SIRKeystream_keystream(key, iv, nbytes))


def sir_encrypt_hex(key_hex: str, iv_hex: str, plaintext_hex: str) -> str:
    """Encrypt hex plaintext and return hex ciphertext."""
    key = hex_to_bytes_fixed(key_hex, 16)
    iv = hex_to_bytes_fixed(iv_hex, 8)
    plaintext = bytes.fromhex(plaintext_hex)
    return bytes_to_hex(SIRKeystream_encrypt(key, iv, plaintext))


def sir_decrypt_hex(key_hex: str, iv_hex: str, ciphertext_hex: str) -> str:
    """Decrypt hex ciphertext and return hex plaintext."""
    key = hex_to_bytes_fixed(key_hex, 16)
    iv = hex_to_bytes_fixed(iv_hex, 8)
    ciphertext = bytes.fromhex(ciphertext_hex)
    return bytes_to_hex(SIRKeystream_decrypt(key, iv, ciphertext))


# ============================================================
# Self-test / demonstration
# ============================================================

def _demo() -> None:
    key_hex = "00000000000000000000000000000000"
    iv_hex = "0000000000000000"
    pt_hex = "00000000000000000000000000000000"

    print("=" * 64)
    print("SIR Keystream Golden Reference Model Demo")
    print("=" * 64)
    print("Key       :", key_hex)
    print("IV        :", iv_hex)
    print("Plaintext :", pt_hex)

    key = hex_to_bytes_fixed(key_hex, 16)
    iv = hex_to_bytes_fixed(iv_hex, 8)
    pt = bytes.fromhex(pt_hex)

    cipher = SIRKeystream(key, iv)
    p_hex, l_hex = cipher.state_as_hex()
    print("State after warm-up:")
    print("  P =", p_hex)
    print("  L =", l_hex)

    # Reinitialize for encryption so demo is clean
    ct = sir_encrypt(key, iv, pt)
    dec = sir_decrypt(key, iv, ct)
    ks = sir_keystream(key, iv, len(pt))

    print("Keystream :", ks.hex())
    print("Ciphertext:", ct.hex())
    print("Decrypted :", dec.hex())
    print("PASS      :", dec == pt)
    print("=" * 64)


if __name__ == "__main__":
    _demo()