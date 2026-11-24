/*
 * sir_xor_wrapper.v
 * Byte-stream encrypt/decrypt wrapper: XORs input bytes with SIR keystream bytes.
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
 * Pulse start while ready = 1 to load key/iv. Then, for each byte:
 * present data_in with data_in_valid while data_in_ready = 1; the result
 * appears on data_out with data_out_valid for one cycle.
 *
 * The core produces a keystream byte every 8 clocks and cannot be paused.
 * Each input byte is XORed with the next keystream byte that arrives after
 * the input byte is accepted. A keystream byte that arrives while no input
 * byte is waiting for it is lost, and every later output is then XORed with
 * the wrong keystream byte. ks_dropped goes high when that happens and stays
 * high until reset. Outputs produced while ks_dropped is low are correct.
 */

`timescale 1ns/1ps

module sir_xor_wrapper (
    input              clk,
    input              rst,
    input              start,
    input      [127:0] key,
    input      [63:0]  iv,

    input      [7:0]   data_in,
    input              data_in_valid,
    output reg         data_in_ready,

    output reg [7:0]   data_out,
    output reg         data_out_valid,

    output             ready,
    output reg         ks_dropped
);

    wire        ks_ready;
    wire        ks_valid;
    wire [7:0]  ks_byte;
    reg         core_start;

    sir_core u_core (
        .clk     (clk),
        .rst     (rst),
        .start   (core_start),
        .key     (key),
        .iv      (iv),
        .ready   (ks_ready),
        .valid   (ks_valid),
        .ks_byte (ks_byte)
    );

    assign ready = ks_ready;

    localparam [1:0] ST_IDLE      = 2'd0;
    localparam [1:0] ST_WAIT_DATA = 2'd1;
    localparam [1:0] ST_WAIT_KS   = 2'd2;
    localparam [1:0] ST_OUT       = 2'd3;

    reg [1:0] state_reg, state_next;
    reg [7:0] data_buf_reg, data_buf_next;

    reg       data_in_ready_next;
    reg [7:0] data_out_next;
    reg       data_out_valid_next;
    reg       core_start_next;
    reg       ks_dropped_next;

    always @(*) begin
        state_next          = state_reg;
        data_buf_next       = data_buf_reg;
        data_in_ready_next  = 1'b0;
        data_out_next       = data_out;
        data_out_valid_next = 1'b0;
        core_start_next     = 1'b0;
        ks_dropped_next     = ks_dropped;

        // Keystream byte with no input byte waiting for it
        if (ks_valid && state_reg != ST_WAIT_KS && state_reg != ST_IDLE)
            ks_dropped_next = 1'b1;

        case (state_reg)
            ST_IDLE: begin
                if (start && ks_ready) begin
                    core_start_next = 1'b1;
                    ks_dropped_next = 1'b0;
                    state_next      = ST_WAIT_DATA;
                end
            end

            ST_WAIT_DATA: begin
                data_in_ready_next = 1'b1;
                if (data_in_valid) begin
                    data_buf_next = data_in;
                    state_next    = ST_WAIT_KS;
                end
            end

            ST_WAIT_KS: begin
                if (ks_valid) begin
                    data_out_next       = data_buf_reg ^ ks_byte;
                    data_out_valid_next = 1'b1;
                    state_next          = ST_OUT;
                end
            end

            ST_OUT: begin
                state_next = ST_WAIT_DATA;
            end

            default: begin
                state_next = ST_IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg      <= ST_IDLE;
            data_buf_reg   <= 8'd0;
            data_in_ready  <= 1'b0;
            data_out       <= 8'd0;
            data_out_valid <= 1'b0;
            core_start     <= 1'b0;
            ks_dropped     <= 1'b0;
        end else begin
            state_reg      <= state_next;
            data_buf_reg   <= data_buf_next;
            data_in_ready  <= data_in_ready_next;
            data_out       <= data_out_next;
            data_out_valid <= data_out_valid_next;
            core_start     <= core_start_next;
            ks_dropped     <= ks_dropped_next;
        end
    end

endmodule
