#!/usr/bin/env python3
#
# check_models.py
# Checks that the Python and C models agree with each other and with kat/sir_kat.csv.
#
# Author      : Prof. W.A. Susantha Wijesinghe
# Email       : susantha@wyb.ac.lk
# Website     : susanthawijesinghe.com
# Date        : 24/11/2026
#
# Copyright   : © 2026  W.A. Susantha Wijesinghe
# License     : MIT (see LICENSE)
#
"""Usage: python3 model/check_models.py <path-to-compiled-sir.c> [n_random]

1. Every vector in kat/sir_kat.csv is regenerated with the Python model
   and with the C model and compared byte for byte.
2. n_random (default 1000) random key/IV pairs are run through both
   models, 256 keystream bytes each, and compared.
Exits with status 1 on any mismatch.
"""

import csv
import random
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from sir import SIR  # noqa: E402

KAT = HERE.parent / "kat" / "sir_kat.csv"


def c_keystream(binary: str, key: str, iv: str, nbytes: int) -> str:
    out = subprocess.run([binary, key, iv, str(nbytes)],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def main(argv) -> int:
    if len(argv) not in (2, 3):
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 1
    binary = argv[1]
    n_random = int(argv[2]) if len(argv) == 3 else 1000

    kat_pass = kat_total = 0
    with KAT.open() as f:
        for row in csv.DictReader(f):
            kat_total += 1
            key, iv, ks = row["key"], row["iv"], row["keystream"]
            nbytes = len(ks) // 2
            py = SIR(bytes.fromhex(key), bytes.fromhex(iv)).keystream(nbytes).hex()
            c = c_keystream(binary, key, iv, nbytes)
            ok = py == ks and c == ks
            kat_pass += ok
            if not ok:
                print(f"KAT {row['index']} MISMATCH  python_ok={py == ks}  c_ok={c == ks}")

    rnd = random.Random(1)
    rand_pass = 0
    for _ in range(n_random):
        key = bytes(rnd.getrandbits(8) for _ in range(16))
        iv = bytes(rnd.getrandbits(8) for _ in range(8))
        py = SIR(key, iv).keystream(256).hex()
        c = c_keystream(binary, key.hex(), iv.hex(), 256)
        if py == c:
            rand_pass += 1
        else:
            print(f"random MISMATCH key={key.hex()} iv={iv.hex()}")

    print(f"KAT vectors (Python and C vs file): {kat_pass} / {kat_total} passed")
    print(f"Random pairs (Python vs C, 256 bytes each): {rand_pass} / {n_random} passed")
    ok = kat_pass == kat_total and rand_pass == n_random
    print("OVERALL RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
