/*
 * tb_sir_xor_wrapper.v
 * Testbench for sir_xor_wrapper: encrypt/decrypt round trip at three input rates.
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
 * For every KAT vector and each input rate:
 *   rate 0: back-to-back (next byte offered as soon as data_in_ready is high)
 *   rate 1: one byte every 8 clocks
 *   rate 2: random gap of 0-40 clocks before each byte
 * the plaintext is encrypted, the wrapper is reset and restarted with the
 * same key/IV, and the ciphertext it produced is decrypted.
 *
 * Checks, per output byte:
 *   - while ks_dropped is low, the encrypted byte must equal the KAT
 *     ciphertext and the decrypted byte must equal the plaintext;
 *   - a wrong byte with ks_dropped low is an undetected error.
 * Rates 0 and 1 must never drop a keystream byte. Rate 2 is expected to
 * drop bytes on long gaps; there ks_dropped must be high for every wrong byte.
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
    localparam integer PT  = 24 + NB;     // offsets inside one record
    localparam integer CT  = 24 + 2 * NB;
    localparam integer MAX_GAP = 40;

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
    wire        ks_dropped;

    reg [7:0]   kat [0:NV*REC-1];
    reg [8*256-1:0] kat_file;

    reg [7:0]   in_buf  [0:NB-1];
    reg [7:0]   out_buf [0:NB-1];
    reg         drop_at [0:NB-1];  // ks_dropped seen with this output byte
    reg [7:0]   enc_out [0:NB-1];
    reg         enc_drop[0:NB-1];

    integer v, j, base, rate, seed, gap;
    integer cycle, last_send;
    integer good, flagged, undetected, clean_vectors, vec_clean;
    integer total_undetected, rate01_drops, total_good, total_flagged;

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
        .ready          (ready),
        .ks_dropped     (ks_dropped)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial cycle = 0;
    always @(posedge clk) cycle <= cycle + 1;

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

    task wait_before_send;
        begin
            if (rate == 1) begin
                while (cycle < last_send + 8) @(posedge clk);
            end else if (rate == 2) begin
                gap = {$random(seed)} % (MAX_GAP + 1);
                repeat (gap) @(posedge clk);
            end
        end
    endtask

    // One pass through the wrapper: in_buf in, out_buf/drop_at out.
    task run_pass;
        begin
            apply_reset();
            while (ready !== 1'b1) @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            last_send = cycle;

            for (j = 0; j < NB; j = j + 1) begin
                wait_before_send();
                while (data_in_ready !== 1'b1) @(posedge clk);
                data_in       <= in_buf[j];
                data_in_valid <= 1'b1;
                last_send = cycle;
                @(posedge clk);
                data_in_valid <= 1'b0;

                while (data_out_valid !== 1'b1) @(posedge clk);
                out_buf[j] = data_out;
                drop_at[j] = ks_dropped;
                @(posedge clk);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("kat=%s", kat_file))
            kat_file = "kat/sir_kat.mem";
        $readmemh(kat_file, kat);

        seed             = 2026;
        total_undetected = 0;
        rate01_drops     = 0;
        total_good       = 0;
        total_flagged    = 0;

        for (rate = 0; rate < 3; rate = rate + 1) begin
            good          = 0;
            flagged       = 0;
            undetected    = 0;
            clean_vectors = 0;

            for (v = 0; v < NV; v = v + 1) begin
                base = v * REC;
                for (j = 0; j < 16; j = j + 1) key[127 - 8*j -: 8] = kat[base + j];
                for (j = 0; j < 8;  j = j + 1) iv[63 - 8*j -: 8]   = kat[base + 16 + j];

                // Encrypt the plaintext
                for (j = 0; j < NB; j = j + 1) in_buf[j] = kat[base + PT + j];
                run_pass();
                for (j = 0; j < NB; j = j + 1) begin
                    enc_out[j]  = out_buf[j];
                    enc_drop[j] = drop_at[j];
                end

                // Decrypt what the wrapper produced
                for (j = 0; j < NB; j = j + 1) in_buf[j] = enc_out[j];
                run_pass();

                vec_clean = 1;
                for (j = 0; j < NB; j = j + 1) begin
                    if (enc_drop[j] || drop_at[j]) begin
                        flagged   = flagged + 1;
                        vec_clean = 0;
                    end else if (enc_out[j] === kat[base + CT + j] &&
                                 out_buf[j] === kat[base + PT + j]) begin
                        good = good + 1;
                    end else begin
                        undetected = undetected + 1;
                        vec_clean  = 0;
                        $display("  rate %0d vector %0d byte %0d: wrong output with ks_dropped low",
                                 rate, v + 1, j);
                    end
                end
                clean_vectors = clean_vectors + vec_clean;
            end

            $display("rate %0d (%0s): %0d / %0d vectors round-trip cleanly; bytes: %0d correct, %0d flagged by ks_dropped, %0d undetected errors",
                     rate, (rate == 0) ? "back-to-back" : (rate == 1) ? "every 8 clocks" : "random 0-40 gaps",
                     clean_vectors, NV, good, flagged, undetected);

            total_undetected = total_undetected + undetected;
            total_good       = total_good + good;
            total_flagged    = total_flagged + flagged;
            if (rate < 2)
                rate01_drops = rate01_drops + flagged;
        end

        $display("tb_sir_xor_wrapper: %0d bytes correct, %0d flagged, %0d undetected errors",
                 total_good, total_flagged, total_undetected);
        $display("OVERALL RESULT: %s",
                 (total_undetected == 0 && rate01_drops == 0 &&
                  total_good + total_flagged == 3 * NV * NB) ? "PASS" : "FAIL");
        $finish;
    end

endmodule
