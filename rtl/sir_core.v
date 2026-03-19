// ============================================================================
// Title      : SIR Core (Sparse-Interaction Keystream Generator)
// File       : sir_core.v
// Author     : Dr. W. A. Susantha Wijesinghe
// email      : susantha@wyb.ac.lk
// Date       : 19-03-2026
//
// Description:
// ------------
// This module implements the core keystream generation logic of the
// SIR (Sparse Interaction Register) architecture.
//
// The design consists of:
//   - A 64-bit nonlinear primary state updated via sparse local interaction
//   - A 64-bit auxiliary LFSR providing round-dependent perturbation
//
// The primary state evolves through a uniform Boolean update rule applied
// across a sparsely connected neighbourhood, enabling parallel combinational
// mixing instead of sequential propagation.
//
// This module produces one keystream bit per clock cycle after initialization.
//
// Notes:
// ------
// - Designed for lightweight hardware implementation (FPGA/ASIC)
// - Intended for research and evaluation purposes
// - Reference Python model available in sir_reference_model.py
//
// ============================================================================

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

    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_LOAD   = 2'd1;
    localparam [1:0] ST_WARMUP = 2'd2;
    localparam [1:0] ST_RUN    = 2'd3;

    localparam [63:0] INIT_CONST = 64'h9E3779B97F4A7C15;
    localparam integer WARMUP_ROUNDS = 32;

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

    // ------------------------------------------------------------
    // Rule-A
    // ------------------------------------------------------------
    function rule_a;
        input x0;
        input x1;
        input x2;
        input x3;
        begin
            rule_a = 1'b1 ^ x2 ^ (x0 & x2) ^ (x1 & x2) ^ (x1 & x3) ^ (x0 & x2 & x3);
        end
    endfunction

    // ------------------------------------------------------------
    // Rotate-left-by-1 for MSB-first 64-bit vector
    // ------------------------------------------------------------
    function [63:0] rotl1_64;
        input [63:0] x;
        begin
            rotl1_64 = {x[62:0], x[63]};
        end
    endfunction

    // ------------------------------------------------------------
    // Map Python-style bit index idx in [0..63]
    // to RTL vector bit position [63-idx]
    // ------------------------------------------------------------
    function get_bit_idx;
        input [63:0] x;
        input integer idx;
        begin
            get_bit_idx = x[63 - idx];
        end
    endfunction

    // ------------------------------------------------------------
    // Output function using Python-style tap indices:
    // taps = {0,16,32,48} -> RTL positions {63,47,31,15}
    // ------------------------------------------------------------
    function output_func;
        input [63:0] P;
        reg parity_rest;
        begin
            parity_rest =
                ^{P[62:48], P[46:32], P[30:16], P[14:0]};

            output_func =
                rule_a(P[63], P[47], P[31], P[15]) ^ parity_rest;
        end
    endfunction

    // ------------------------------------------------------------
    // Round datapath
    // ------------------------------------------------------------
    always @(*) begin
        // Primary-state update
        // For Python index i:
        //   P'_i = RuleA(P_i, P_{i-1}, P_{i+1}, P_{i+8}) XOR P_{i+2}
        for (i = 0; i < 64; i = i + 1) begin
            P_round_raw[63 - i] =
                rule_a(
                    get_bit_idx(P_reg, i),
                    get_bit_idx(P_reg, (i + 63) % 64),
                    get_bit_idx(P_reg, (i + 1)  % 64),
                    get_bit_idx(P_reg, (i + 8)  % 64)
                ) ^
                get_bit_idx(P_reg, (i + 2) % 64);
        end

        L_round = {
            L_reg[62:0],
            (L_reg[63] ^ L_reg[62] ^ L_reg[60] ^ L_reg[59])
        };

        // Round-key extraction from Python indices
        // [0,8,16,24,32,40,48,56] -> RTL [63,55,47,39,31,23,15,7]
        rk_round[0] = L_round[63];
        rk_round[1] = L_round[55];
        rk_round[2] = L_round[47];
        rk_round[3] = L_round[39];
        rk_round[4] = L_round[31];
        rk_round[5] = L_round[23];
        rk_round[6] = L_round[15];
        rk_round[7] = L_round[7];

        // Inject into Python P[0..7] -> RTL [63:56]
        P_round_inj = P_round_raw;
        P_round_inj[63] = P_round_raw[63] ^ rk_round[0];
        P_round_inj[62] = P_round_raw[62] ^ rk_round[1];
        P_round_inj[61] = P_round_raw[61] ^ rk_round[2];
        P_round_inj[60] = P_round_raw[60] ^ rk_round[3];
        P_round_inj[59] = P_round_raw[59] ^ rk_round[4];
        P_round_inj[58] = P_round_raw[58] ^ rk_round[5];
        P_round_inj[57] = P_round_raw[57] ^ rk_round[6];
        P_round_inj[56] = P_round_raw[56] ^ rk_round[7];

        // Output bit from updated + injected primary state
        z_bit = output_func(P_round_inj);
    end

    // ------------------------------------------------------------
    // Control / next-state logic
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
                ready_next       = 1'b1;
                valid_next       = 1'b0;
                bit_ctr_next     = 3'd0;
                ks_byte_next     = 8'd0;
                warmup_ctr_next  = 6'd0;

                if (start) begin
                    state_next = ST_LOAD;
                    ready_next = 1'b0;
                end
            end

            ST_LOAD: begin
                // Initialization:
                // P0 = K0 XOR V
                // L0 = K1 XOR RotL1(V) XOR C
                //
                // key[127:64] = K0
                // key[63:0]   = K1
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

                if (warmup_ctr_reg == (WARMUP_ROUNDS - 1)) begin
                    warmup_ctr_next = 6'd0;
                    bit_ctr_next    = 3'd0;
                    ks_byte_next    = 8'd0;
                    state_next      = ST_RUN;
                end else begin
                    warmup_ctr_next = warmup_ctr_reg + 6'd1;
                end
            end

            ST_RUN: begin
                P_next = P_round_inj;
                L_next = L_round;

                // Assemble byte MSB-first:
                // first produced bit -> ks_byte[7]
                // ...
                // eighth produced bit -> ks_byte[0]
                ks_byte_next = ks_byte_reg;
                ks_byte_next[7 - bit_ctr_reg] = z_bit;

                if (bit_ctr_reg == 3'd7) begin
                    bit_ctr_next     = 3'd0;
                    valid_next       = 1'b1;
                    ks_byte_out_next = ks_byte_next;
                end else begin
                    bit_ctr_next     = bit_ctr_reg + 3'd1;
                end
            end

            default: begin
                state_next = ST_IDLE;
                ready_next = 1'b1;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sequential registers
    // ------------------------------------------------------------
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