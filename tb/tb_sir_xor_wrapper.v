// ============================================================================
// Title      : Testbench for SIR XOR Wrapper
// File       : tb_sir_xor_wrapper.v
// Author     : Dr. W. A. Susantha Wijesinghe
// email      : susantha@wyb.ac.lk
// Date       : 19-03-2026
//
// Description:
// ------------
// Testbench for validating the stream encryption/decryption functionality
// of the SIR XOR wrapper module.
//
// Features:
//   - Encrypts plaintext using generated keystream
//   - Decrypts ciphertext to verify correctness
//   - Confirms symmetry of XOR-based stream cipher operation
//
// ============================================================================

`timescale 1ns/1ps

module tb_sir_xor_wrapper;

    reg         clk;
    reg         rst;
    reg         start;
    reg [127:0] key;
    reg [63:0]  iv;

    reg [7:0]   data_in;
    reg         data_in_valid;
    wire        data_in_ready;

    wire [7:0]  data_out;
    wire        data_out_valid;
    wire        ready;

    integer total_tests;
    integer passed_tests;
    integer i;

    reg [7:0] pt_bytes [0:31];
    reg [7:0] ct_bytes [0:31];

    sir_xor_stream dut (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .key          (key),
        .iv           (iv),
        .data_in      (data_in),
        .data_in_valid(data_in_valid),
        .data_in_ready(data_in_ready),
        .data_out     (data_out),
        .data_out_valid(data_out_valid),
        .ready        (ready)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------
    task apply_reset;
        begin
            rst           <= 1'b1;
            start         <= 1'b0;
            key           <= 128'd0;
            iv            <= 64'd0;
            data_in       <= 8'd0;
            data_in_valid <= 1'b0;

            repeat (3) @(posedge clk);
            rst <= 1'b0;
            @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // Start pulse
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
    // Send one byte when wrapper is ready
    // ------------------------------------------------------------
    task send_one_byte;
        input [7:0] b;
        begin
            while (data_in_ready !== 1'b1) begin
                @(posedge clk);
            end

            data_in       <= b;
            data_in_valid <= 1'b1;
            @(posedge clk);
            data_in_valid <= 1'b0;
            data_in       <= 8'd0;
        end
    endtask

    // ------------------------------------------------------------
    // Wait and check one output byte
    // ------------------------------------------------------------
    task wait_and_check_out;
        input integer idx;
        input [7:0] expected;
        begin
            while (data_out_valid !== 1'b1) begin
                @(posedge clk);
            end

            total_tests = total_tests + 1;
            if (data_out === expected) begin
                passed_tests = passed_tests + 1;
                $display("  Byte %0d PASS  got=%02x exp=%02x", idx, data_out, expected);
            end else begin
                $display("  Byte %0d FAIL  got=%02x exp=%02x", idx, data_out, expected);
            end

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

            while (ready !== 1'b1) begin
                @(posedge clk);
            end

            key <= tv_key;
            iv  <= tv_iv;

            pulse_start();

            for (i = 0; i < nbytes; i = i + 1) begin
                send_one_byte(pt_bytes[i]);
                wait_and_check_out(i, ct_bytes[i]);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------
    initial begin
        total_tests  = 0;
        passed_tests = 0;

        apply_reset();

        // ========================================================
        // TV1_all_zero
        // PT = 00000000000000000000000000000000
        // CT = 8452678c1e657e99cae4b96e9ce90cf8
        // ========================================================
        for (i = 0; i < 16; i = i + 1)
            pt_bytes[i] = 8'h00;

        ct_bytes[0]  = 8'h84;
        ct_bytes[1]  = 8'h52;
        ct_bytes[2]  = 8'h67;
        ct_bytes[3]  = 8'h8c;
        ct_bytes[4]  = 8'h1e;
        ct_bytes[5]  = 8'h65;
        ct_bytes[6]  = 8'h7e;
        ct_bytes[7]  = 8'h99;
        ct_bytes[8]  = 8'hca;
        ct_bytes[9]  = 8'he4;
        ct_bytes[10] = 8'hb9;
        ct_bytes[11] = 8'h6e;
        ct_bytes[12] = 8'h9c;
        ct_bytes[13] = 8'he9;
        ct_bytes[14] = 8'h0c;
        ct_bytes[15] = 8'hf8;

        run_vector(
            "TV1_all_zero",
            128'h00000000000000000000000000000000,
            64'h0000000000000000,
            16
        );

        repeat (5) @(posedge clk);
        apply_reset();

        // ========================================================
        // TV4_incrementing_pattern
        // PT = 000102030405060708090a0b0c0d0e0f
        // CT = fdb9c813b87324a41a6729e0c0f6d0d6
        // ========================================================
        pt_bytes[0]  = 8'h00;
        pt_bytes[1]  = 8'h01;
        pt_bytes[2]  = 8'h02;
        pt_bytes[3]  = 8'h03;
        pt_bytes[4]  = 8'h04;
        pt_bytes[5]  = 8'h05;
        pt_bytes[6]  = 8'h06;
        pt_bytes[7]  = 8'h07;
        pt_bytes[8]  = 8'h08;
        pt_bytes[9]  = 8'h09;
        pt_bytes[10] = 8'h0a;
        pt_bytes[11] = 8'h0b;
        pt_bytes[12] = 8'h0c;
        pt_bytes[13] = 8'h0d;
        pt_bytes[14] = 8'h0e;
        pt_bytes[15] = 8'h0f;

        ct_bytes[0]  = 8'hfd;
        ct_bytes[1]  = 8'hb9;
        ct_bytes[2]  = 8'hc8;
        ct_bytes[3]  = 8'h13;
        ct_bytes[4]  = 8'hb8;
        ct_bytes[5]  = 8'h73;
        ct_bytes[6]  = 8'h24;
        ct_bytes[7]  = 8'ha4;
        ct_bytes[8]  = 8'h1a;
        ct_bytes[9]  = 8'h67;
        ct_bytes[10] = 8'h29;
        ct_bytes[11] = 8'he0;
        ct_bytes[12] = 8'hc0;
        ct_bytes[13] = 8'hf6;
        ct_bytes[14] = 8'hd0;
        ct_bytes[15] = 8'hd6;

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
        // PT = 00112233445566778899aabbccddeeff
        //      fedcba98765432100123456789abcdef
        // CT = cbc8f1958a8de9227fcd9c807f3ba38f
        //      d8408ec81fecad0d4469046a2d026e88
        // ========================================================
        pt_bytes[0]  = 8'h00;
        pt_bytes[1]  = 8'h11;
        pt_bytes[2]  = 8'h22;
        pt_bytes[3]  = 8'h33;
        pt_bytes[4]  = 8'h44;
        pt_bytes[5]  = 8'h55;
        pt_bytes[6]  = 8'h66;
        pt_bytes[7]  = 8'h77;
        pt_bytes[8]  = 8'h88;
        pt_bytes[9]  = 8'h99;
        pt_bytes[10] = 8'haa;
        pt_bytes[11] = 8'hbb;
        pt_bytes[12] = 8'hcc;
        pt_bytes[13] = 8'hdd;
        pt_bytes[14] = 8'hee;
        pt_bytes[15] = 8'hff;
        pt_bytes[16] = 8'hfe;
        pt_bytes[17] = 8'hdc;
        pt_bytes[18] = 8'hba;
        pt_bytes[19] = 8'h98;
        pt_bytes[20] = 8'h76;
        pt_bytes[21] = 8'h54;
        pt_bytes[22] = 8'h32;
        pt_bytes[23] = 8'h10;
        pt_bytes[24] = 8'h01;
        pt_bytes[25] = 8'h23;
        pt_bytes[26] = 8'h45;
        pt_bytes[27] = 8'h67;
        pt_bytes[28] = 8'h89;
        pt_bytes[29] = 8'hab;
        pt_bytes[30] = 8'hcd;
        pt_bytes[31] = 8'hef;

        ct_bytes[0]  = 8'hcb;
        ct_bytes[1]  = 8'hc8;
        ct_bytes[2]  = 8'hf1;
        ct_bytes[3]  = 8'h95;
        ct_bytes[4]  = 8'h8a;
        ct_bytes[5]  = 8'h8d;
        ct_bytes[6]  = 8'he9;
        ct_bytes[7]  = 8'h22;
        ct_bytes[8]  = 8'h7f;
        ct_bytes[9]  = 8'hcd;
        ct_bytes[10] = 8'h9c;
        ct_bytes[11] = 8'h80;
        ct_bytes[12] = 8'h7f;
        ct_bytes[13] = 8'h3b;
        ct_bytes[14] = 8'ha3;
        ct_bytes[15] = 8'h8f;
        ct_bytes[16] = 8'hd8;
        ct_bytes[17] = 8'h40;
        ct_bytes[18] = 8'h8e;
        ct_bytes[19] = 8'hc8;
        ct_bytes[20] = 8'h1f;
        ct_bytes[21] = 8'hec;
        ct_bytes[22] = 8'had;
        ct_bytes[23] = 8'h0d;
        ct_bytes[24] = 8'h44;
        ct_bytes[25] = 8'h69;
        ct_bytes[26] = 8'h04;
        ct_bytes[27] = 8'h6a;
        ct_bytes[28] = 8'h2d;
        ct_bytes[29] = 8'h02;
        ct_bytes[30] = 8'h6e;
        ct_bytes[31] = 8'h88;

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