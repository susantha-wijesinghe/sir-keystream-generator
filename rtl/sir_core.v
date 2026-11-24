/*
 * sir_core.v
 * SIR keystream generator core: key/IV load, 32-round warm-up, one keystream bit per clock.
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
 * Interface
 *   start   : one-cycle pulse while ready = 1 loads key/iv and starts warm-up
 *   ks_byte : keystream byte, valid for one cycle when valid = 1
 *             (first keystream bit in ks_byte[7])
 *
 * Bit numbering
 *   The model (model/sir.py) numbers state bits 0..63 with bit 0 first.
 *   In this RTL, model index i is vector bit [63 - i]; get_bit_idx() does
 *   the mapping so the update equations read the same as in the model.
 */

`timescale 1ns/1ps

module sir_core (
    input              clk,
    input              rst,
    input              start,
    input      [127:0] key,
    input      [63:0]  iv,
    output reg         ready,
    output reg         valid,
    output reg [7:0]   ks_byte
);

    localparam integer LONG_OFFSET   = 16;  // neighbourhood: P[i-1], P[i+1], P[i+16]
    localparam integer COUPLING      = 12;  // extra XOR term P[i+12]
    localparam integer TAP0          = 0;   // output function taps
    localparam integer TAP1          = 13;
    localparam integer TAP2          = 29;
    localparam integer TAP3          = 46;
    localparam integer WARMUP_ROUNDS = 32;
    localparam [63:0]  INIT_CONST    = 64'h9E3779B97F4A7C15;

    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_LOAD   = 2'd1;
    localparam [1:0] ST_WARMUP = 2'd2;
    localparam [1:0] ST_RUN    = 2'd3;

    reg [1:0]  state_reg, state_next;
    reg [63:0] P_reg, P_next;
    reg [63:0] L_reg, L_next;
    reg [5:0]  warmup_ctr_reg, warmup_ctr_next;
    reg [2:0]  bit_ctr_reg, bit_ctr_next;
    reg [7:0]  ks_byte_reg, ks_byte_next;

    reg        ready_next;
    reg        valid_next;
    reg [7:0]  ks_byte_out_next;

    reg [63:0] P_round_raw;
    reg [63:0] P_round_inj;
    reg [63:0] L_round;
    reg [7:0]  rk_round;
    reg        z_bit;

    integer i;

    function rule_a;
        input x0;
        input x1;
        input x2;
        input x3;
        begin
            rule_a = 1'b1 ^ x2 ^ (x0 & x2) ^ (x1 & x2) ^ (x1 & x3) ^ (x0 & x2 & x3);
        end
    endfunction

    function [63:0] rotl1_64;
        input [63:0] x;
        begin
            rotl1_64 = {x[62:0], x[63]};
        end
    endfunction

    // Model bit index idx -> vector bit [63 - idx]
    function get_bit_idx;
        input [63:0] x;
        input integer idx;
        begin
            get_bit_idx = x[63 - idx];
        end
    endfunction

    // z = RULEA(P[TAP0..TAP3]) XOR parity of the other 60 bits
    function output_func;
        input [63:0] P;
        integer k;
        reg parity_rest;
        begin
            parity_rest = 1'b0;
            for (k = 0; k < 64; k = k + 1) begin
                if (k != TAP0 && k != TAP1 && k != TAP2 && k != TAP3)
                    parity_rest = parity_rest ^ get_bit_idx(P, k);
            end
            output_func = rule_a(get_bit_idx(P, TAP0), get_bit_idx(P, TAP1),
                                 get_bit_idx(P, TAP2), get_bit_idx(P, TAP3))
                          ^ parity_rest;
        end
    endfunction

    // ------------------------------------------------------------
    // Round datapath
    // ------------------------------------------------------------
    always @(*) begin
        // P'[i] = RULEA(P[i], P[i-1], P[i+1], P[i+16]) XOR P[i+12]
        for (i = 0; i < 64; i = i + 1) begin
            P_round_raw[63 - i] =
                rule_a(get_bit_idx(P_reg, i),
                       get_bit_idx(P_reg, (i + 63) % 64),
                       get_bit_idx(P_reg, (i + 1) % 64),
                       get_bit_idx(P_reg, (i + LONG_OFFSET) % 64))
                ^ get_bit_idx(P_reg, (i + COUPLING) % 64);
        end

        // LFSR, taps L[0], L[1], L[3], L[4]
        L_round = {L_reg[62:0], (L_reg[63] ^ L_reg[62] ^ L_reg[60] ^ L_reg[59])};

        // Round key L[0], L[8], ..., L[56] of the updated LFSR
        rk_round[0] = L_round[63];
        rk_round[1] = L_round[55];
        rk_round[2] = L_round[47];
        rk_round[3] = L_round[39];
        rk_round[4] = L_round[31];
        rk_round[5] = L_round[23];
        rk_round[6] = L_round[15];
        rk_round[7] = L_round[7];

        // Injected into P[0..7]
        P_round_inj        = P_round_raw;
        P_round_inj[63:56] = P_round_raw[63:56] ^ {rk_round[0], rk_round[1], rk_round[2], rk_round[3],
                                                   rk_round[4], rk_round[5], rk_round[6], rk_round[7]};

        z_bit = output_func(P_round_inj);
    end

    // ------------------------------------------------------------
    // Control
    // ------------------------------------------------------------
    always @(*) begin
        state_next       = state_reg;
        P_next           = P_reg;
        L_next           = L_reg;
        warmup_ctr_next  = warmup_ctr_reg;
        bit_ctr_next     = bit_ctr_reg;
        ks_byte_next     = ks_byte_reg;
        ready_next       = 1'b0;
        valid_next       = 1'b0;
        ks_byte_out_next = ks_byte;

        case (state_reg)
            ST_IDLE: begin
                ready_next      = 1'b1;
                bit_ctr_next    = 3'd0;
                ks_byte_next    = 8'd0;
                warmup_ctr_next = 6'd0;
                if (start) begin
                    state_next = ST_LOAD;
                    ready_next = 1'b0;
                end
            end

            ST_LOAD: begin
                // P = K0 ^ IV,  L = K1 ^ RotL1(IV) ^ C,  with K0 = key[127:64], K1 = key[63:0]
                P_next          = key[127:64] ^ iv;
                L_next          = key[63:0] ^ rotl1_64(iv) ^ INIT_CONST;
                warmup_ctr_next = 6'd0;
                bit_ctr_next    = 3'd0;
                ks_byte_next    = 8'd0;
                state_next      = ST_WARMUP;
            end

            ST_WARMUP: begin
                P_next = P_round_inj;
                L_next = L_round;
                if (warmup_ctr_reg == WARMUP_ROUNDS - 1) begin
                    warmup_ctr_next = 6'd0;
                    state_next      = ST_RUN;
                end else begin
                    warmup_ctr_next = warmup_ctr_reg + 6'd1;
                end
            end

            ST_RUN: begin
                P_next = P_round_inj;
                L_next = L_round;

                // Collect bits MSB first; emit the byte after the 8th bit
                ks_byte_next = ks_byte_reg;
                ks_byte_next[7 - bit_ctr_reg] = z_bit;

                if (bit_ctr_reg == 3'd7) begin
                    bit_ctr_next     = 3'd0;
                    valid_next       = 1'b1;
                    ks_byte_out_next = ks_byte_next;
                end else begin
                    bit_ctr_next = bit_ctr_reg + 3'd1;
                end
            end

            default: begin
                state_next = ST_IDLE;
                ready_next = 1'b1;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg      <= ST_IDLE;
            P_reg          <= 64'd0;
            L_reg          <= 64'd0;
            warmup_ctr_reg <= 6'd0;
            bit_ctr_reg    <= 3'd0;
            ks_byte_reg    <= 8'd0;
            ks_byte        <= 8'd0;
            ready          <= 1'b1;
            valid          <= 1'b0;
        end else begin
            state_reg      <= state_next;
            P_reg          <= P_next;
            L_reg          <= L_next;
            warmup_ctr_reg <= warmup_ctr_next;
            bit_ctr_reg    <= bit_ctr_next;
            ks_byte_reg    <= ks_byte_next;
            ks_byte        <= ks_byte_out_next;
            ready          <= ready_next;
            valid          <= valid_next;
        end
    end

endmodule
