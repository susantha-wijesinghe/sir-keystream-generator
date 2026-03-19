#!/usr/bin/env python3

"""
===============================================================================
Title      : SIR Test Vector Generator
File       : sir_generate_test_vectors.py
Author     : Dr. W. A. Susantha Wijesinghe
email      : susantha@wyb.ac.lk
Date       : 19-03-2026

Description:
------------
This script generates deterministic test vectors for the SIR keystream
generator using the Python reference model.

Functionality:
--------------
- Generates keystream sequences for fixed key/IV pairs
- Produces reproducible outputs for hardware verification
- Exports test vectors in CSV and TXT formats

Outputs:
--------
- sir_test_vectors.csv
- sir_test_vectors.txt

Usage:
------
Run the script to generate test vectors:

    python sir_generate_test_vectors.py

These vectors are used to validate the Verilog implementation.

===============================================================================
"""

from __future__ import annotations

import csv
import random
from typing import List, Dict

from sir_reference_model import (
    SIRKeystream,
    sir_encrypt,
    sir_decrypt,
    sir_keystream,
    hex_to_bytes_fixed,
    bytes_to_hex,
)


# ============================================================
# Helpers
# ============================================================

def fixed_hex_bytes(hex_str: str, nbytes: int) -> bytes:
    return hex_to_bytes_fixed(hex_str, nbytes)


def random_bytes_from_seed(seed: int, nbytes: int) -> bytes:
    rng = random.Random(seed)
    return bytes(rng.getrandbits(8) for _ in range(nbytes))


def make_vector(name: str, key: bytes, iv: bytes, pt: bytes) -> Dict[str, str]:
    # Capture post-warm-up state
    cipher_for_state = SIRKeystream(key, iv)
    p_hex, l_hex = cipher_for_state.state_as_hex()

    # Clean fresh runs for functional outputs
    ks = sir_keystream(key, iv, len(pt))
    ct = sir_encrypt(key, iv, pt)
    dec = sir_decrypt(key, iv, ct)

    return {
        "name": name,
        "key_hex": bytes_to_hex(key),
        "iv_hex": bytes_to_hex(iv),
        "plaintext_hex": bytes_to_hex(pt),
        "state_P_after_warmup_hex": p_hex,
        "state_L_after_warmup_hex": l_hex,
        "keystream_hex": bytes_to_hex(ks),
        "ciphertext_hex": bytes_to_hex(ct),
        "decrypted_hex": bytes_to_hex(dec),
        "pass": str(dec == pt),
    }


def print_vector(tv: Dict[str, str]) -> None:
    print("=" * 72)
    print(tv["name"])
    print("  Key              :", tv["key_hex"])
    print("  IV               :", tv["iv_hex"])
    print("  Plaintext        :", tv["plaintext_hex"])
    print("  State P (warmup) :", tv["state_P_after_warmup_hex"])
    print("  State L (warmup) :", tv["state_L_after_warmup_hex"])
    print("  Keystream        :", tv["keystream_hex"])
    print("  Ciphertext       :", tv["ciphertext_hex"])
    print("  Decrypted        :", tv["decrypted_hex"])
    print("  PASS             :", tv["pass"])


# ============================================================
# Main vector generation
# ============================================================

def main() -> None:
    vectors: List[Dict[str, str]] = []

    # Standard plaintext length used for the base set
    pt_len = 16

    # 1. All-zero baseline
    vectors.append(make_vector(
        name="TV1_all_zero",
        key=fixed_hex_bytes("00000000000000000000000000000000", 16),
        iv=fixed_hex_bytes("0000000000000000", 8),
        pt=fixed_hex_bytes("00000000000000000000000000000000", 16),
    ))

    # 2. All-one key, zero IV, zero plaintext
    vectors.append(make_vector(
        name="TV2_all_one_key",
        key=fixed_hex_bytes("ffffffffffffffffffffffffffffffff", 16),
        iv=fixed_hex_bytes("0000000000000000", 8),
        pt=fixed_hex_bytes("00000000000000000000000000000000", 16),
    ))

    # 3. Zero key, all-one IV, zero plaintext
    vectors.append(make_vector(
        name="TV3_all_one_iv",
        key=fixed_hex_bytes("00000000000000000000000000000000", 16),
        iv=fixed_hex_bytes("ffffffffffffffff", 8),
        pt=fixed_hex_bytes("00000000000000000000000000000000", 16),
    ))

    # 4. Incrementing key / IV / plaintext
    vectors.append(make_vector(
        name="TV4_incrementing_pattern",
        key=fixed_hex_bytes("000102030405060708090a0b0c0d0e0f", 16),
        iv=fixed_hex_bytes("0001020304050607", 8),
        pt=fixed_hex_bytes("000102030405060708090a0b0c0d0e0f", 16),
    ))

    # 5. Alternating patterns
    vectors.append(make_vector(
        name="TV5_alternating_pattern",
        key=fixed_hex_bytes("aa55aa55aa55aa55aa55aa55aa55aa55", 16),
        iv=fixed_hex_bytes("55aa55aa55aa55aa", 8),
        pt=fixed_hex_bytes("aa55aa55aa55aa55aa55aa55aa55aa55", 16),
    ))

    # 6. Reverse-like pattern
    vectors.append(make_vector(
        name="TV6_reverse_pattern",
        key=fixed_hex_bytes("f0e1d2c3b4a5968778695a4b3c2d1e0f", 16),
        iv=fixed_hex_bytes("8877665544332211", 8),
        pt=fixed_hex_bytes("00112233445566778899aabbccddeeff", 16),
    ))

    # 7-10. Seeded random deterministic vectors
    seed_specs = [
        ("TV7_seeded_random_1", 101),
        ("TV8_seeded_random_2", 202),
        ("TV9_seeded_random_3", 303),
        ("TV10_seeded_random_4", 404),
    ]

    for name, seed in seed_specs:
        key = random_bytes_from_seed(seed, 16)
        iv = random_bytes_from_seed(seed + 1000, 8)
        pt = random_bytes_from_seed(seed + 2000, pt_len)
        vectors.append(make_vector(name=name, key=key, iv=iv, pt=pt))

    # 11. Longer plaintext test
    vectors.append(make_vector(
        name="TV11_long_plaintext_32B",
        key=fixed_hex_bytes("00112233445566778899aabbccddeeff", 16),
        iv=fixed_hex_bytes("0123456789abcdef", 8),
        pt=fixed_hex_bytes(
            "00112233445566778899aabbccddeeff"
            "fedcba98765432100123456789abcdef",
            32
        ),
    ))

    # Console output
    print("\nSIR-Keystream Test Vectors\n")
    for tv in vectors:
        print_vector(tv)

    # Save CSV
    csv_file = "sir_test_vectors.csv"
    with open(csv_file, "w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "name",
                "key_hex",
                "iv_hex",
                "plaintext_hex",
                "state_P_after_warmup_hex",
                "state_L_after_warmup_hex",
                "keystream_hex",
                "ciphertext_hex",
                "decrypted_hex",
                "pass",
            ],
        )
        writer.writeheader()
        for tv in vectors:
            writer.writerow(tv)

    # Save TXT
    txt_file = "sir_test_vectors.txt"
    with open(txt_file, "w") as f:
        f.write("Deterministic Test Vectors\n\n")
        for tv in vectors:
            f.write("=" * 72 + "\n")
            f.write(tv["name"] + "\n")
            f.write(f"  Key              : {tv['key_hex']}\n")
            f.write(f"  IV               : {tv['iv_hex']}\n")
            f.write(f"  Plaintext        : {tv['plaintext_hex']}\n")
            f.write(f"  State P (warmup) : {tv['state_P_after_warmup_hex']}\n")
            f.write(f"  State L (warmup) : {tv['state_L_after_warmup_hex']}\n")
            f.write(f"  Keystream        : {tv['keystream_hex']}\n")
            f.write(f"  Ciphertext       : {tv['ciphertext_hex']}\n")
            f.write(f"  Decrypted        : {tv['decrypted_hex']}\n")
            f.write(f"  PASS             : {tv['pass']}\n")

    print("\nSaved:")
    print(" ", csv_file)
    print(" ", txt_file)


if __name__ == "__main__":
    main()