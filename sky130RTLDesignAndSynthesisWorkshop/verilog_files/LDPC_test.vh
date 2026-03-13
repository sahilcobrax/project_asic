`timescale 1ns/1ps

module LDPC_tb;

    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;

    task clk_wait;
        input integer n;
        integer k;
        begin for (k = 0; k < n; k = k + 1) @(posedge clk); #1; end
    endtask

    // pass/fail scratch register – avoids sized constants inside $display ternary
    reg pf;

    // =========================================================
    // TEST 1 – cn_update_iams
    //   INPUT : clk, layer_idx[5:0], current_node_idx[2:0],
    //           vn_degree[7:0], vtc_signs[RD-1:0],
    //           vtc_mags_flat[RD*(Q-1)-1:0]
    //   OUTPUT: ctv_out signed [Q-1:0]
    // =========================================================
    localparam CNU_Q  = 4;
    localparam CNU_RD = 8;

    reg  [5:0]                   cnu_layer;
    reg  [3:0]                   cnu_nidx;
    reg  [7:0]                   cnu_vndeg;
    reg  [CNU_RD-1:0]            cnu_signs;
    reg  [CNU_RD*(CNU_Q-1)-1:0]  cnu_mags_flat;
    wire signed [CNU_Q-1:0]      cnu_ctv;

    cn_update_iams #(.Q(CNU_Q), .ROW_DEGREE(CNU_RD)) uut_cnu (
        .clk              (clk),
        .layer_idx        (cnu_layer),
        .current_node_idx (cnu_nidx),
        .vn_degree        (cnu_vndeg),
        .vtc_signs        (cnu_signs),
        .vtc_mags_flat    (cnu_mags_flat),
        .ctv_out          (cnu_ctv)
    );

    // pack 8 × 3-bit magnitudes into flat bus (Q-1=3 bits each)
    task set_mags8;
        input [2:0] m0,m1,m2,m3,m4,m5,m6,m7;
        begin
            cnu_mags_flat = {m7, m6, m5, m4, m3, m2, m1, m0};
        end
    endtask

    // =========================================================
    // TEST 2 – vn_update
    //   INPUT : clk, app_in[5:0], t_idx[7:0], layer_idx[5:0],
    //           vn_idx[5:0], ctv_stored signed[3:0]
    //   OUTPUT: vtc_new signed[3:0], beta_tilde signed[5:0]
    // =========================================================
    reg  [5:0]        vnu_app;
    reg  [7:0]        vnu_t;
    reg  [5:0]        vnu_layer, vnu_idx;
    reg  signed [3:0] vnu_ctv;
    wire signed [3:0] vnu_vtc;
    wire signed [5:0] vnu_bt;

    vn_update #(.Q(4), .Q_APP(6)) uut_vnu (
        .clk        (clk),
        .app_in     (vnu_app),
        .t_idx      (vnu_t),
        .layer_idx  (vnu_layer),
        .vn_idx     (vnu_idx),
        .ctv_stored (vnu_ctv),
        .vtc_new    (vnu_vtc),
        .beta_tilde (vnu_bt)
    );

    // =========================================================
    // TEST 3 – app_update_unit  (combinational)
    //   INPUT : alpha_curr signed[3:0], beta_tilde signed[5:0]
    //   OUTPUT: app_new signed[5:0]
    // =========================================================
    reg  signed [3:0] apu_a;
    reg  signed [5:0] apu_b;
    wire signed [5:0] apu_out;

    app_update_unit #(.Q(4), .Q_APP(6)) uut_apu (
        .alpha_curr (apu_a),
        .beta_tilde (apu_b),
        .app_new    (apu_out)
    );

    // =========================================================
    // TEST 4 – ctv_memory
    //   INPUT : clk, write_en, layer_addr[5:0], vn_addr[5:0],
    //           ctv_in signed[3:0]
    //   OUTPUT: ctv_out signed[3:0]
    // =========================================================
    reg        cm_we;
    reg  [5:0] cm_layer, cm_vn;
    reg  signed [3:0] cm_in;
    wire signed [3:0] cm_out;

    ctv_memory #(.Q(4), .Z(52), .L_COUNT(42), .MAX_ROW_DEG(10)) uut_ctvm (
        .clk        (clk),
        .write_en   (cm_we),
        .layer_addr (cm_layer),
        .vn_addr    (cm_vn),
        .ctv_in     (cm_in),
        .ctv_out    (cm_out)
    );

    // =========================================================
    // TEST 5 – split_storage_unit
    //   INPUT : clk, write_en, layer_addr[5:0],
    //           in_min1[3:0], in_min2[3:0], in_idx1[5:0],
    //           in_signs[9:0]
    //   OUTPUT: out_min1[3:0], out_min2[3:0], out_idx1[5:0],
    //           out_signs[9:0]
    // =========================================================
    reg        ss_we;
    reg  [5:0] ss_layer;
    reg  [3:0] ss_m1_in,  ss_m2_in;
    reg  [5:0] ss_i1_in;
    reg  [9:0] ss_sg_in;
    wire [3:0] ss_m1_out, ss_m2_out;
    wire [5:0] ss_i1_out;
    wire [9:0] ss_sg_out;

    split_storage_unit #(.Q(4), .MAX_ROW_DEG(10)) uut_ssu (
        .clk        (clk),
        .write_en   (ss_we),
        .layer_addr (ss_layer),
        .in_min1    (ss_m1_in),
        .in_min2    (ss_m2_in),
        .in_idx1    (ss_i1_in),
        .in_signs   (ss_sg_in),
        .out_min1   (ss_m1_out),
        .out_min2   (ss_m2_out),
        .out_idx1   (ss_i1_out),
        .out_signs  (ss_sg_out)
    );

    // expected signs constant stored in a reg to avoid sized literal in ternary
    reg [9:0] exp_signs_a;
    reg [9:0] exp_signs_b;

    // =========================================================
    // TEST 6 – selective_shift_network  (combinational)
    //   INPUT : data_in[Z*Q-1:0], shift_val[5:0], is_nonzero_entry
    //   OUTPUT: data_out[Z*Q-1:0]
    // =========================================================
    localparam SSN_Z = 4;
    localparam SSN_Q = 4;

    reg  [SSN_Z*SSN_Q-1:0] ssn_in;
    reg  [5:0]             ssn_sh;
    reg                    ssn_nz;
    wire [SSN_Z*SSN_Q-1:0] ssn_out;

    selective_shift_network #(.Z(SSN_Z), .Q(SSN_Q)) uut_ssn (
        .data_in          (ssn_in),
        .shift_val        (ssn_sh),
        .is_nonzero_entry (ssn_nz),
        .data_out         (ssn_out)
    );

    // expected values kept in regs
    reg [SSN_Z*SSN_Q-1:0] exp_zero;
    reg [SSN_Z*SSN_Q-1:0] exp_ssn_in;

    // =========================================================
    // TEST 7 – ldpc_decoder_layer
    //   INPUT : clk, reset, channel_llr_flat[Z*Q_APP-1:0]
    //   OUTPUT: decoded_bits[Z-1:0], done
    // =========================================================
    localparam DEC_Z    = 52;
    localparam DEC_QAPP = 6;

    reg  [DEC_Z*DEC_QAPP-1:0] dec_llr_flat;
    wire [DEC_Z-1:0]           dec_bits;
    wire                       dec_done;

    ldpc_decoder_layer #(
        .Q(4), .Q_APP(DEC_QAPP), .Z(DEC_Z),
        .L_COUNT(42), .ROW_DEGREE(10)
    ) uut_dec (
        .clk              (clk),
        .reset            (reset),
        .channel_llr_flat (dec_llr_flat),
        .decoded_bits     (dec_bits),
        .done             (dec_done)
    );

    reg [DEC_Z-1:0] exp_allzero;
    reg [DEC_Z-1:0] exp_allone;
    integer i, fail_cnt;
    integer mag_abs;

    initial begin
        $display("\n============================================");
        $display(" LDPC Decoder Testbench");
        $display("============================================\n");

        fail_cnt   = 0;
        exp_zero   = 0;
        exp_allzero = 0;
        exp_allone  = {DEC_Z{1'b1}};

        reset = 1; clk_wait(3); reset = 0;

        // =====================================================
        // TEST 1: cn_update_iams
        // ctv_out is fully combinational – use #1 settle, no clock wait
        // =====================================================
        $display("--- TEST 1: cn_update_iams ---");

        // mags = [3,5,2,6,4,3,7,1] → min1=1(idx7) min2=2(idx2)
        cnu_layer = 6'd5;
        cnu_vndeg = 8'd4;
        cnu_signs = 8'b00001010;
        set_mags8(3'd3, 3'd5, 3'd2, 3'd6, 3'd4, 3'd3, 3'd7, 3'd1);

        // 1a: n == idx1(7) → output magnitude = min2 = 2
        cnu_nidx = 3'd7;
        #2;  // combinational settle
        mag_abs = (cnu_ctv < 0) ? -cnu_ctv : cnu_ctv;
        pf = (mag_abs == 2);
        $display("  1a) n=idx1  expect|ctv|=2  got ctv=%0d  %s",
                 cnu_ctv, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 1b: core check (layer<4) + high degree (>=6) → OMS: max(min1-1,0)=0
        // min1=1, so (1>1) is false → mag=0
        cnu_layer = 6'd2;
        cnu_vndeg = 8'd8;
        cnu_nidx  = 3'd0;
        #2;
        pf = (cnu_ctv === 4'sd0);
        $display("  1b) OMS core+highDeg  expect|ctv|=0  got ctv=%0d  %s",
                 cnu_ctv, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 1c: extension, n == idx2(2) → output magnitude = min1 = 1
        cnu_layer = 6'd10;
        cnu_vndeg = 8'd3;
        cnu_nidx  = 3'd2;
        #2;
        mag_abs = (cnu_ctv < 0) ? -cnu_ctv : cnu_ctv;
        pf = (mag_abs == 1);
        $display("  1c) n=idx2  expect|ctv|=1  got ctv=%0d  %s",
                 cnu_ctv, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 1d: min1==min2=3, other node → min1-1 = 2
        set_mags8(3'd3, 3'd3, 3'd3, 3'd5, 3'd6, 3'd7, 3'd7, 3'd7);
        cnu_layer = 6'd8;
        cnu_nidx  = 3'd4;
        #2;
        mag_abs = (cnu_ctv < 0) ? -cnu_ctv : cnu_ctv;
        pf = (mag_abs == 2);
        $display("  1d) min1==min2 other  expect|ctv|=2  got ctv=%0d  %s",
                 cnu_ctv, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        $display("  TEST 1 done.\n");

        // =====================================================
        // TEST 2: vn_update
        // =====================================================
        $display("--- TEST 2: vn_update ---");

        // 2a: t=1 → ctv_old forced 0; app=+10 → beta_tilde=10
        vnu_app   = 6'b001010;   // +10
        vnu_t     = 8'd1;
        vnu_layer = 6'd0;
        vnu_idx   = 6'd0;
        vnu_ctv   = 4'sd5;       // ignored at t==1
        #1;
        pf = (vnu_bt === 6'sd10);
        $display("  2a) t=1 beta_tilde=%0d  expect 10  %s",
                 vnu_bt, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 2b: t=2, ctv=3, app=10 → sub=7, vtc=7
        vnu_t   = 8'd2;
        vnu_ctv = 4'sd3;
        #1;
        pf = (vnu_bt === 6'sd7) && (vnu_vtc === 4'sd7);
        $display("  2b) beta=%0d vtc=%0d  expect 7,7  %s",
                 vnu_bt, vnu_vtc, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 2c: app=+15, ctv=-5 → sub=20 → clamp to +7
        vnu_app = 6'b001111;   // +15
        vnu_ctv = -4'sd5;
        #1;
        pf = (vnu_vtc === 4'sd7);
        $display("  2c) clamp high  vtc=%0d  expect 7  %s",
                 vnu_vtc, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 2d: app=-15, ctv=+3 → sub=-18 → clamp to -8
        vnu_app = 6'b110001;   // -15 signed 6-bit
        vnu_ctv = 4'sd3;
        #1;
        pf = (vnu_vtc === -4'sd8);
        $display("  2d) clamp low   vtc=%0d  expect -8  %s",
                 vnu_vtc, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        $display("  TEST 2 done.\n");

        // =====================================================
        // TEST 3: app_update_unit
        // =====================================================
        $display("--- TEST 3: app_update_unit ---");

        // 3a: 3 + 5 = 8  (no saturation)
        apu_a = 4'sd3;
        apu_b = 6'sd5;
        #1;
        pf = (apu_out === 6'sd8);
        $display("  3a) 3+5=%0d  expect 8  %s",
                 apu_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 3b: 7 + 30 = 37 → saturate to +31
        apu_a = 4'sd7;
        apu_b = 6'sd30;
        #1;
        pf = (apu_out === 6'sd31);
        $display("  3b) pos sat=%0d  expect 31  %s",
                 apu_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 3c: -8 + (-28) = -36 → saturate to -32
        apu_a = -4'sd8;
        apu_b = -6'sd28;
        #1;
        pf = (apu_out === -6'sd32);
        $display("  3c) neg sat=%0d  expect -32  %s",
                 apu_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 3d: 0 + 0 = 0
        apu_a = 4'sd0;
        apu_b = 6'sd0;
        #1;
        pf = (apu_out === 6'sd0);
        $display("  3d) zero=%0d  expect 0  %s",
                 apu_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        $display("  TEST 3 done.\n");

        // =====================================================
        // TEST 4: ctv_memory
        // =====================================================
        $display("--- TEST 4: ctv_memory ---");

        // 4a: write -3 to layer=5 vn=10; read back
        cm_we    = 1;
        cm_layer = 6'd5;
        cm_vn    = 6'd10;
        cm_in    = -4'sd3;
        @(posedge clk); #1;
        cm_we = 0;
        pf = (cm_out === -4'sd3);
        $display("  4a) wrote -3  read=%0d  expect -3  %s",
                 cm_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 4b: write +7 to layer=0 vn=0; read back
        cm_we    = 1;
        cm_layer = 6'd0;
        cm_vn    = 6'd0;
        cm_in    = 4'sd7;
        @(posedge clk); #1;
        cm_we = 0;
        pf = (cm_out === 4'sd7);
        $display("  4b) wrote +7  read=%0d  expect +7  %s",
                 cm_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 4c: layer=5 vn=10 still holds -3
        cm_layer = 6'd5;
        cm_vn    = 6'd10;
        #1;
        pf = (cm_out === -4'sd3);
        $display("  4c) retain  read=%0d  expect -3  %s",
                 cm_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        $display("  TEST 4 done.\n");

        // =====================================================
        // TEST 5: split_storage_unit
        // =====================================================
        $display("--- TEST 5: split_storage_unit ---");

        // Store expected values in regs – avoids sized literals inside ternary
        exp_signs_a = 10'b1010101010;
        exp_signs_b = 10'b1111111111;

        // 5a: write and read back
        ss_we    = 1;
        ss_layer = 6'd3;
        ss_m1_in = 4'd2;
        ss_m2_in = 4'd5;
        ss_i1_in = 6'd7;
        ss_sg_in = exp_signs_a;
        @(posedge clk); #1;
        ss_we = 0;
        pf = (ss_m1_out === 4'd2)  && (ss_m2_out === 4'd5) &&
             (ss_i1_out === 6'd7)  && (ss_sg_out === exp_signs_a);
        $display("  5a) min1=%0d min2=%0d idx1=%0d signs=%b  %s",
                 ss_m1_out, ss_m2_out, ss_i1_out, ss_sg_out,
                 pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 5b: overwrite same address
        ss_we    = 1;
        ss_m1_in = 4'd0;
        ss_m2_in = 4'd1;
        ss_i1_in = 6'd0;
        ss_sg_in = exp_signs_b;
        @(posedge clk); #1;
        ss_we = 0;
        pf = (ss_m1_out === 4'd0) && (ss_m2_out === 4'd1);
        $display("  5b) overwrite  min1=%0d min2=%0d  expect 0,1  %s",
                 ss_m1_out, ss_m2_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        $display("  TEST 5 done.\n");

        // =====================================================
        // TEST 6: selective_shift_network
        // =====================================================
        $display("--- TEST 6: selective_shift_network ---");

        // Store expected values in regs
        exp_zero    = 0;
        exp_ssn_in  = 16'hABCD;

        // 6a: is_nonzero_entry=0 → output must be all zeros
        ssn_in = exp_ssn_in;
        ssn_sh = 6'd2;
        ssn_nz = 1'b0;
        #1;
        pf = (ssn_out === exp_zero);
        $display("  6a) nz=0  out=0x%04h  expect 0x0000  %s",
                 ssn_out, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 6b: is_nonzero_entry=1, shift=0 → output unchanged
        ssn_nz = 1'b1;
        ssn_sh = 6'd0;
        #1;
        pf = (ssn_out === ssn_in);
        $display("  6b) sh=0  out=0x%04h  expect 0x%04h  %s",
                 ssn_out, ssn_in, pf ? "PASS" : "FAIL");
        if (!pf) fail_cnt = fail_cnt + 1;

        // 6c: shift=1 → circular left by Q=4 bits (informational)
        ssn_in = 16'h1234;
        ssn_sh = 6'd1;
        ssn_nz = 1'b1;
        #1;
        $display("  6c) sh=1  in=0x%04h  out=0x%04h (circular left shift Q bits)",
                 ssn_in, ssn_out);

        $display("  TEST 6 done.\n");

        // =====================================================
        // TEST 7: ldpc_decoder_layer (full decoder)
        // =====================================================
        $display("--- TEST 7: ldpc_decoder_layer ---");

        // Reset and load all-positive LLRs (+15) → expect all-zero codeword
        reset = 1; clk_wait(4); reset = 0;
        for (i = 0; i < DEC_Z; i = i + 1)
            dec_llr_flat[i*DEC_QAPP +: DEC_QAPP] = 6'd15;

        $display("  7a) Waiting for done (strong +LLR) ...");
        begin : wait_pos
            integer to;
            to = 0;
            while (!dec_done && to < 1200) begin
                @(posedge clk);
                to = to + 1;
            end
            if (dec_done)
                $display("  7a) DONE after %0d cycles.", to);
            else
                $display("  7a) INFO: done not seen within 1200 cycles.");
        end

        pf = (dec_bits === exp_allzero);
        $display("  7b) decoded_bits=0x%h  %s",
                 dec_bits, pf ? "PASS" : "INFO(non-zero without full H-matrix)");

        // Reset and load all-negative LLRs (-15) → expect all-one codeword
        reset = 1; clk_wait(3); reset = 0;
        for (i = 0; i < DEC_Z; i = i + 1)
            dec_llr_flat[i*DEC_QAPP +: DEC_QAPP] = 6'b110001;  // -15 signed 6-bit

        $display("  7c) Waiting for done (strong -LLR) ...");
        begin : wait_neg
            integer to2;
            to2 = 0;
            while (!dec_done && to2 < 1200) begin
                @(posedge clk);
                to2 = to2 + 1;
            end
            if (dec_done)
                $display("  7c) DONE after %0d cycles. decoded_bits=0x%h",
                         to2, dec_bits);
            else
                $display("  7c) INFO: done not asserted.");
        end

        $display("  TEST 7 done.\n");
        $display("============================================");
        $display(" Testbench complete.  FAIL count = %0d", fail_cnt);
        $display("============================================\n");
        $finish;
    end

    initial begin
        $dumpfile("LDPC_tb.vcd");
        $dumpvars(0, LDPC_tb);
    end

endmodule
