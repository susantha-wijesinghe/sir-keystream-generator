// ============================================================================
// Title      : Testbench for SIR Core
// File       : tb_sir_core.v
// Author     : Dr. W. A. Susantha Wijesinghe
// email      : susantha@wyb.ac.lk
// Date       : 19-03-2026
//
// Description:
// ------------
// Testbench for verifying the functionality of the SIR core module.
//
// Features:
//   - Applies test vectors generated from the Python reference model
//   - Verifies keystream correctness against expected outputs
//   - Supports deterministic validation using known key/IV pairs
//
// Usage:
// ------
// Run simulation and compare generated keystream with reference values
// provided in test_vectors files.
//
// ============================================================================

`timescale 1ns/1ps


module tb_sir_core;

    reg         clk;
    reg         rst;
    reg         start;
    reg [127:0] key;
    reg [63:0]  iv;

    wire        ready;
    wire        valid;
    wire [7:0]  ks_byte;

    integer total_tests;
    integer passed_tests;

    reg [7:0] exp_bytes [0:31];
    integer i;

    // DUT
    sir_core dut (
        .clk    (clk),
        .rst    (rst),
        .start  (start),
        .key    (key),
        .iv     (iv),
        .ready  (ready),
        .valid  (valid),
        .ks_byte(ks_byte)
    );

    // ------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz equivalent
    end

    // ------------------------------------------------------------
    // Utility: wait for one valid byte and compare
    // ------------------------------------------------------------
    task wait_and_check_byte;
        input integer idx;
        input [7:0] expected;
        begin
            while (valid !== 1'b1) begin
                @(posedge clk);
            end

            total_tests = total_tests + 1;
            if (ks_byte === expected) begin
                passed_tests = passed_tests + 1;
                $display("  Byte %0d PASS  got=%02x exp=%02x", idx, ks_byte, expected);
            end else begin
                $display("  Byte %0d FAIL  got=%02x exp=%02x", idx, ks_byte, expected);
            end

            @(posedge clk); // move past valid pulse
        end
    endtask

    // ------------------------------------------------------------
    // Utility: pulse start
    // ------------------------------------------------------------
    task pulse_start;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------
    // Utility: reset DUT
    // ------------------------------------------------------------
    task apply_reset;
        begin
            rst   <= 1'b1;
            start <= 1'b0;
            key   <= 128'd0;
            iv    <= 64'd0;

            repeat (3) @(posedge clk);
            rst <= 1'b0;
            @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // Run one vector
    // ------------------------------------------------------------
    task run_vector;
        input [8*40-1:0] name;
        input [127:0] tv_key;
        input [63:0]  tv_iv;
        input integer nbytes;
        begin
            $display("================================================================");
            $display("%0s", name);
            $display("  key = %032x", tv_key);
            $display("  iv  = %016x", tv_iv);

            // Wait until DUT ready
            while (ready !== 1'b1) begin
                @(posedge clk);
            end

            key <= tv_key;
            iv  <= tv_iv;

            pulse_start();

            for (i = 0; i < nbytes; i = i + 1) begin
                wait_and_check_byte(i, exp_bytes[i]);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Main stimulus
    // ------------------------------------------------------------
    initial begin
        total_tests  = 0;
        passed_tests = 0;

        apply_reset();

        // ========================================================
        // TV1_all_zero
        // Key       : 00000000000000000000000000000000
        // IV        : 0000000000000000
        // Keystream : 8452678c1e657e99cae4b96e9ce90cf8
        // ========================================================
        exp_bytes[0]  = 8'h84;
        exp_bytes[1]  = 8'h52;
        exp_bytes[2]  = 8'h67;
        exp_bytes[3]  = 8'h8c;
        exp_bytes[4]  = 8'h1e;
        exp_bytes[5]  = 8'h65;
        exp_bytes[6]  = 8'h7e;
        exp_bytes[7]  = 8'h99;
        exp_bytes[8]  = 8'hca;
        exp_bytes[9]  = 8'he4;
        exp_bytes[10] = 8'hb9;
        exp_bytes[11] = 8'h6e;
        exp_bytes[12] = 8'h9c;
        exp_bytes[13] = 8'he9;
        exp_bytes[14] = 8'h0c;
        exp_bytes[15] = 8'hf8;

        run_vector(
            "TV1_all_zero",
            128'h00000000000000000000000000000000,
            64'h0000000000000000,
            16
        );

        // Small separation
        repeat (5) @(posedge clk);
        apply_reset();

        // ========================================================
        // TV4_incrementing_pattern
        // Key       : 000102030405060708090a0b0c0d0e0f
        // IV        : 0001020304050607
        // Keystream : fdb8ca10bc7622a3126e23ebccfbded9
        // ========================================================
        exp_bytes[0]  = 8'hfd;
        exp_bytes[1]  = 8'hb8;
        exp_bytes[2]  = 8'hca;
        exp_bytes[3]  = 8'h10;
        exp_bytes[4]  = 8'hbc;
        exp_bytes[5]  = 8'h76;
        exp_bytes[6]  = 8'h22;
        exp_bytes[7]  = 8'ha3;
        exp_bytes[8]  = 8'h12;
        exp_bytes[9]  = 8'h6e;
        exp_bytes[10] = 8'h23;
        exp_bytes[11] = 8'heb;
        exp_bytes[12] = 8'hcc;
        exp_bytes[13] = 8'hfb;
        exp_bytes[14] = 8'hde;
        exp_bytes[15] = 8'hd9;

        run_vector(
            "TV4_incrementing_pattern",
            128'h000102030405060708090a0b0c0d0e0f,
            64'h0001020304050607,
            16
        );

        repeat (5) @(posedge clk);
        apply_reset();

        // ========================================================
        // TV11_long_plaintext_32B
        // Key       : 00112233445566778899aabbccddeeff
        // IV        : 0123456789abcdef
        // Keystream : cbd9d3a6ced88f55f754363bb3e64d70
        //             269c345069b89f1d454a410da4a9a367
        // ========================================================
        exp_bytes[0]  = 8'hcb;
        exp_bytes[1]  = 8'hd9;
        exp_bytes[2]  = 8'hd3;
        exp_bytes[3]  = 8'ha6;
        exp_bytes[4]  = 8'hce;
        exp_bytes[5]  = 8'hd8;
        exp_bytes[6]  = 8'h8f;
        exp_bytes[7]  = 8'h55;
        exp_bytes[8]  = 8'hf7;
        exp_bytes[9]  = 8'h54;
        exp_bytes[10] = 8'h36;
        exp_bytes[11] = 8'h3b;
        exp_bytes[12] = 8'hb3;
        exp_bytes[13] = 8'he6;
        exp_bytes[14] = 8'h4d;
        exp_bytes[15] = 8'h70;
        exp_bytes[16] = 8'h26;
        exp_bytes[17] = 8'h9c;
        exp_bytes[18] = 8'h34;
        exp_bytes[19] = 8'h50;
        exp_bytes[20] = 8'h69;
        exp_bytes[21] = 8'hb8;
        exp_bytes[22] = 8'h9f;
        exp_bytes[23] = 8'h1d;
        exp_bytes[24] = 8'h45;
        exp_bytes[25] = 8'h4a;
        exp_bytes[26] = 8'h41;
        exp_bytes[27] = 8'h0d;
        exp_bytes[28] = 8'ha4;
        exp_bytes[29] = 8'ha9;
        exp_bytes[30] = 8'ha3;
        exp_bytes[31] = 8'h67;

        run_vector(
            "TV11_long_plaintext_32B",
            128'h00112233445566778899aabbccddeeff,
            64'h0123456789abcdef,
            32
        );

        $display("================================================================");
        $display("Test Summary: %0d / %0d byte checks passed", passed_tests, total_tests);
        if (passed_tests == total_tests) begin
            $display("OVERALL RESULT: PASS");
        end else begin
            $display("OVERALL RESULT: FAIL");
        end
        $display("================================================================");

        #20;
        $finish;
    end

endmodule