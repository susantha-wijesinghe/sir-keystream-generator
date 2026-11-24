/*
 * tb_sir_xor_wrapper.v
 * Testbench for sir_xor_wrapper: encrypts and decrypts the KAT plaintexts.
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
 * For each vector: encrypt the plaintext and compare with the ciphertext
 * in kat/sir_kat.mem, then restart with the same key/IV, decrypt the
 * ciphertext and compare with the plaintext.
 *
 * Run from the repository root (the KAT path is relative):
 *   iverilog -g2005 -o build/tb_sir_xor_wrapper.vvp \
 *       rtl/sir_core.v rtl/sir_xor_wrapper.v tb/tb_sir_xor_wrapper.v
 *   vvp build/tb_sir_xor_wrapper.vvp
 */

`timescale 1ns/1ps

module tb_sir_xor_wrapper;

    localparam integer NV  = 8;
    localparam integer NB  = 64;
    localparam integer REC = 24 + 3 * NB;
    localparam integer KS  = 24;          // offsets inside one record
    localparam integer PT  = 24 + NB;
    localparam integer CT  = 24 + 2 * NB;

    reg         clk;
    reg         rst;
    reg         start;
    reg [127:0] key;
    reg [63:0]  iv;

    reg  [7:0]  data_in;
    reg         data_in_valid;
    wire        data_in_ready;
    wire [7:0]  data_out;
    wire        data_out_valid;
    wire        ready;

    reg [7:0]   kat [0:NV*REC-1];
    reg [8*256-1:0] kat_file;

    integer v, j, base, pass_dir;
    integer total, passed;

    sir_xor_wrapper dut (
        .clk            (clk),
        .rst            (rst),
        .start          (start),
        .key            (key),
        .iv             (iv),
        .data_in        (data_in),
        .data_in_valid  (data_in_valid),
        .data_in_ready  (data_in_ready),
        .data_out       (data_out),
        .data_out_valid (data_out_valid),
        .ready          (ready)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task apply_reset;
        begin
            rst           <= 1'b1;
            start         <= 1'b0;
            data_in       <= 8'd0;
            data_in_valid <= 1'b0;
            repeat (3) @(posedge clk);
            rst <= 1'b0;
            @(posedge clk);
        end
    endtask

    task send_byte;
        input [7:0] b;
        begin
            while (data_in_ready !== 1'b1) @(posedge clk);
            data_in       <= b;
            data_in_valid <= 1'b1;
            @(posedge clk);
            data_in_valid <= 1'b0;
            data_in       <= 8'd0;
        end
    endtask

    task check_byte;
        input integer idx;
        input [7:0] expected;
        begin
            while (data_out_valid !== 1'b1) @(posedge clk);
            total = total + 1;
            if (data_out === expected)
                passed = passed + 1;
            else
                $display("  byte %0d FAIL  got=%02x exp=%02x", idx, data_out, expected);
            @(posedge clk);
        end
    endtask

    // pass_dir 0: plaintext in, ciphertext expected; 1: the reverse
    task run_pass;
        input integer dir;
        integer src, dst;
        begin
            src = (dir == 0) ? PT : CT;
            dst = (dir == 0) ? CT : PT;
            apply_reset();
            while (ready !== 1'b1) @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            for (j = 0; j < NB; j = j + 1) begin
                send_byte(kat[base + src + j]);
                check_byte(j, kat[base + dst + j]);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("kat=%s", kat_file))
            kat_file = "kat/sir_kat.mem";
        $readmemh(kat_file, kat);

        total  = 0;
        passed = 0;

        for (v = 0; v < NV; v = v + 1) begin
            base = v * REC;
            for (j = 0; j < 16; j = j + 1) key[127 - 8*j -: 8] = kat[base + j];
            for (j = 0; j < 8;  j = j + 1) iv[63 - 8*j -: 8]   = kat[base + 16 + j];
            $display("vector %0d  key=%032x  iv=%016x", v + 1, key, iv);
            for (pass_dir = 0; pass_dir < 2; pass_dir = pass_dir + 1)
                run_pass(pass_dir);
        end

        $display("tb_sir_xor_wrapper: %0d / %0d bytes match (encrypt + decrypt)", passed, total);
        $display("OVERALL RESULT: %s", (passed == total && total == 2 * NV * NB) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
