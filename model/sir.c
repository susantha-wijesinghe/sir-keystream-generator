/*
 * sir.c
 * C reference model of the SIR keystream generator (word-level, one instance).
 *
 * Author      : Prof. W.A. Susantha Wijesinghe
 * Email       : susantha@wyb.ac.lk
 * Website     : susanthawijesinghe.com
 * Date        : 24/11/2026
 *
 * Copyright   : © 2026  W.A. Susantha Wijesinghe
 * License     : MIT (see LICENSE)
 */

/*
 * Each 64-bit register is held in one uint64_t with word bit i = P[i]
 * (P[0] = first key/IV bit, as in sir.py). With that layout, reading
 * P[i + r] for all i at once is a rotate right by r, so the whole
 * primary update is a few word operations.
 *
 * Build : cc -O2 -o sir sir.c
 * Usage : ./sir <key_hex32> <iv_hex16> [nbytes]      prints keystream in hex
 *         ./sir -b <key_hex32> <iv_hex16> <nbytes>   writes raw bytes to stdout
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WARMUP_ROUNDS 32
#define OFF_LONG      16u   /* neighbourhood: P[i-1], P[i+1], P[i+16] */
#define COUPLING      12u   /* extra XOR term P[i+12] */
#define TAP0          0u    /* output function taps */
#define TAP1          13u
#define TAP2          29u
#define TAP3          46u
#define INIT_CONSTANT 0x9E3779B97F4A7C15ULL

typedef struct {
    uint64_t P;
    uint64_t L;
} sir_state;

static uint64_t rotr64(uint64_t x, unsigned r)
{
    r &= 63u;
    return r ? (x >> r) | (x << (64u - r)) : x;
}

static uint64_t rotl64(uint64_t x, unsigned r)
{
    r &= 63u;
    return r ? (x << r) | (x >> (64u - r)) : x;
}

static uint64_t bitreverse64(uint64_t x)
{
    x = ((x & 0x5555555555555555ULL) << 1)  | ((x >> 1)  & 0x5555555555555555ULL);
    x = ((x & 0x3333333333333333ULL) << 2)  | ((x >> 2)  & 0x3333333333333333ULL);
    x = ((x & 0x0F0F0F0F0F0F0F0FULL) << 4)  | ((x >> 4)  & 0x0F0F0F0F0F0F0F0FULL);
    x = ((x & 0x00FF00FF00FF00FFULL) << 8)  | ((x >> 8)  & 0x00FF00FF00FF00FFULL);
    x = ((x & 0x0000FFFF0000FFFFULL) << 16) | ((x >> 16) & 0x0000FFFF0000FFFFULL);
    return (x << 32) | (x >> 32);
}

static uint64_t load_be64(const uint8_t *p)
{
    uint64_t v = 0;
    for (int i = 0; i < 8; i++)
        v = (v << 8) | p[i];
    return v;
}

static unsigned parity64(uint64_t x)
{
    x ^= x >> 32;
    x ^= x >> 16;
    x ^= x >> 8;
    x ^= x >> 4;
    x ^= x >> 2;
    x ^= x >> 1;
    return (unsigned)(x & 1u);
}

/* One round: primary update, LFSR step, round-key injection, output bit. */
static int sir_round(sir_state *s)
{
    uint64_t x0 = s->P;
    uint64_t x1 = rotr64(s->P, 63u);        /* P[i-1]  */
    uint64_t x2 = rotr64(s->P, 1u);         /* P[i+1]  */
    uint64_t x3 = rotr64(s->P, OFF_LONG);   /* P[i+16] */
    uint64_t Pn = ~0ULL ^ x2 ^ (x0 & x2) ^ (x1 & x2) ^ (x1 & x3) ^ (x0 & x2 & x3)
                ^ rotr64(s->P, COUPLING);

    /* L taps {0,1,3,4}; shift toward index 0, feedback enters L[63]. */
    uint64_t fb = (s->L ^ (s->L >> 1) ^ (s->L >> 3) ^ (s->L >> 4)) & 1ULL;
    uint64_t Ln = (s->L >> 1) | (fb << 63);

    /* Round key L[0], L[8], ..., L[56] into P[0..7]. */
    uint64_t rk = 0;
    for (unsigned k = 0; k < 8; k++)
        rk |= ((Ln >> (8u * k)) & 1ULL) << k;
    Pn ^= rk;

    unsigned t0 = (unsigned)(Pn >> TAP0) & 1u;
    unsigned t1 = (unsigned)(Pn >> TAP1) & 1u;
    unsigned t2 = (unsigned)(Pn >> TAP2) & 1u;
    unsigned t3 = (unsigned)(Pn >> TAP3) & 1u;
    unsigned r  = 1u ^ t2 ^ (t0 & t2) ^ (t1 & t2) ^ (t1 & t3) ^ (t0 & t2 & t3);

    /* Parity of the 60 non-tap bits = full parity XOR the four taps. */
    unsigned z = r ^ parity64(Pn) ^ t0 ^ t1 ^ t2 ^ t3;

    s->P = Pn;
    s->L = Ln;
    return (int)(z & 1u);
}

/* key: 16 bytes, iv: 8 bytes, big-endian (key[0] holds P[0]..P[7] source). */
static void sir_init(sir_state *s, const uint8_t *key, const uint8_t *iv)
{
    uint64_t k0 = load_be64(key);
    uint64_t k1 = load_be64(key + 8);
    uint64_t v  = load_be64(iv);

    s->P = bitreverse64(k0 ^ v);
    s->L = bitreverse64(k1 ^ rotl64(v, 1) ^ INIT_CONSTANT);

    for (int i = 0; i < WARMUP_ROUNDS; i++)
        sir_round(s);
}

/* Keystream bytes, first bit in the MSB of each byte. */
static uint8_t sir_byte(sir_state *s)
{
    uint8_t b = 0;
    for (int k = 0; k < 8; k++)
        b = (uint8_t)((b << 1) | (uint8_t)sir_round(s));
    return b;
}

static int hex_decode(const char *hex, uint8_t *out, size_t len)
{
    if (strlen(hex) != 2 * len)
        return -1;
    for (size_t i = 0; i < len; i++) {
        unsigned v;
        if (sscanf(hex + 2 * i, "%2x", &v) != 1)
            return -1;
        out[i] = (uint8_t)v;
    }
    return 0;
}

int main(int argc, char **argv)
{
    int raw = 0;
    if (argc > 1 && strcmp(argv[1], "-b") == 0) {
        raw = 1;
        argv++;
        argc--;
    }
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "usage: %s [-b] <key_hex32> <iv_hex16> [nbytes]\n", argv[0]);
        return 1;
    }

    uint8_t key[16], iv[8];
    if (hex_decode(argv[1], key, 16) || hex_decode(argv[2], iv, 8)) {
        fprintf(stderr, "key must be 32 hex digits, iv 16 hex digits\n");
        return 1;
    }
    long nbytes = (argc == 4) ? atol(argv[3]) : 32;

    sir_state s;
    sir_init(&s, key, iv);
    for (long i = 0; i < nbytes; i++) {
        uint8_t b = sir_byte(&s);
        if (raw)
            putchar(b);
        else
            printf("%02x", b);
    }
    if (!raw)
        putchar('\n');
    return 0;
}
