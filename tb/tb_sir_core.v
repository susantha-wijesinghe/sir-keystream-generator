/*
 * tb_sir_core.v
 * Testbench for sir_core: checks the keystream against kat/sir_kat.mem.
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
 * Run from the repository root (the KAT path is relative):
 *   iverilog -g2005 -o build/tb_sir_core.vvp rtl/sir_core.v tb/tb_sir_core.v
 *   vvp build/tb_sir_core.vvp
 * Another KAT file can be given with +kat=<path>.
 */

`timescale 1ns/1ps

module tb_sir_core;

    localparam integer NV  = 8;           // vectors in the KAT file
    localparam integer NB  = 64;          // keystream bytes per vector
    localparam integer REC = 24 + 3 * NB; // bytes per vector in the file

    reg         clk;
    reg         rst;
    reg         start;
    reg [127:0] key;
    reg [63:0]  iv;

    wire        ready;
    wire        valid;
    wire [7:0]  ks_byte;

    reg [7:0]   kat [0:NV*REC-1];
    reg [8*256-1:0] kat_file;

    integer v, j, base;
    integer total, passed;

    sir_core dut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .key     (key),
        .iv      (iv),
        .ready   (ready),
        .valid   (valid),
        .ks_byte (ks_byte)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

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

    initial begin
        if (!$value$plusargs("kat=%s", kat_file))
            kat_file = "kat/sir_kat.mem";
        $readmemh(kat_file, kat);

        total  = 0;
        passed = 0;

        for (v = 0; v < NV; v = v + 1) begin
            base = v * REC;
            apply_reset();

            for (j = 0; j < 16; j = j + 1) key[127 - 8*j -: 8] = kat[base + j];
            for (j = 0; j < 8;  j = j + 1) iv[63 - 8*j -: 8]   = kat[base + 16 + j];
            $display("vector %0d  key=%032x  iv=%016x", v + 1, key, iv);

            while (ready !== 1'b1) @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            for (j = 0; j < NB; j = j + 1) begin
                @(posedge clk);
                while (valid !== 1'b1) @(posedge clk);
                total = total + 1;
                if (ks_byte === kat[base + 24 + j])
                    passed = passed + 1;
                else
                    $display("  byte %0d FAIL  got=%02x exp=%02x", j, ks_byte, kat[base + 24 + j]);
            end
        end

        $display("tb_sir_core: %0d / %0d keystream bytes match", passed, total);
        $display("OVERALL RESULT: %s", (passed == total && total == NV * NB) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
