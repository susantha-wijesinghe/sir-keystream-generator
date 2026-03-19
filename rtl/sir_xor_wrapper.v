// ============================================================================
// Title      : SIR XOR Wrapper (Stream Encryption/Decryption Interface)
// File       : sir_xor_wrapper.v
// Author     : Dr. W. A. Susantha Wijesinghe
// email      : susantha@wyb.ac.lk
// Date       : 19-03-2026
//
// Description:
// ------------
// This module provides a simple stream cipher interface using the SIR core.
//
// Functionality:
//   - Instantiates the SIR keystream generator (sir_core)
//   - XORs generated keystream with input data stream
//   - Supports both encryption and decryption (symmetric operation)
//
// This wrapper enables byte-wise or word-wise processing for practical
// testing and system integration.
//
// Notes:
// ------
// - This is a lightweight demonstration wrapper for evaluation purposes
// - Not intended as a complete cryptographic protocol implementation
// - Security depends on proper key/IV management (external)
//
// ============================================================================

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

    output             ready
);

    // ------------------------------------------------------------
    // Internal connection to keystream core
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Wrapper state
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin
        state_next          = state_reg;
        data_buf_next       = data_buf_reg;
        data_in_ready_next  = 1'b0;
        data_out_next       = data_out;
        data_out_valid_next = 1'b0;
        core_start_next     = 1'b0;

        case (state_reg)

            ST_IDLE: begin
                if (start && ks_ready) begin
                    core_start_next = 1'b1;
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

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state_reg      <= ST_IDLE;
            data_buf_reg   <= 8'd0;
            data_in_ready  <= 1'b0;
            data_out       <= 8'd0;
            data_out_valid <= 1'b0;
            core_start     <= 1'b0;
        end else begin
            state_reg      <= state_next;
            data_buf_reg   <= data_buf_next;
            data_in_ready  <= data_in_ready_next;
            data_out       <= data_out_next;
            data_out_valid <= data_out_valid_next;
            core_start     <= core_start_next;
        end
    end

endmodule