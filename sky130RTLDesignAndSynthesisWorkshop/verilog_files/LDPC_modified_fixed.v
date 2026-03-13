// 1. LAYER MERGING LOGIC
module ldpc_top_controller #(
    parameter L_COUNT    = 42,
    parameter MERGE_FACTOR = 2,
    parameter ROW_DEGREE = 10,
    parameter Q          = 4
)(
    input  wire                           clk,
    input  wire                           reset,
    output reg  [5:0]                     merged_l_idx,
    // vtc_mags_A / vtc_mags_B: packed flat bus, each entry (Q-1) bits wide
    input  wire [ROW_DEGREE*(Q-1)-1:0]    vtc_mags_A,
    input  wire [ROW_DEGREE-1:0]          vtc_signs_A,
    input  wire [ROW_DEGREE*(Q-1)-1:0]    vtc_mags_B,
    input  wire [ROW_DEGREE-1:0]          vtc_signs_B,
    input  wire [7:0]                     vn_degree_A,
    input  wire [7:0]                     vn_degree_B
);
    wire signed [Q-1:0] ctv_out_A, ctv_out_B;

    // Explicit 6-bit wires to prevent 32-bit expansion on layer_idx port
    wire [5:0] layer_idx_A;
    wire [5:0] layer_idx_B;
    assign layer_idx_A = merged_l_idx * 2;
    assign layer_idx_B = (merged_l_idx * 2) + 6'd1;

    always @(posedge clk) begin
        if (reset)
            merged_l_idx <= 0;
        else if (merged_l_idx < (L_COUNT/MERGE_FACTOR) - 1)
            merged_l_idx <= merged_l_idx + 1;
        else
            merged_l_idx <= 0;
    end
wire  ctrl_done_w; // internal wires to catch the outputs
wire [7:0] ctrl_t_idx_w;
wire [5:0] ctrl_l_idx_w;
    // ldpc_merged_controller does NOT have merged_l_idx port – removed
    ldpc_merged_controller merge_ctrl (
        .clk   (clk),
        .reset (reset),
        .done(ctrl_done_w),
        .t_idx(ctrl_t_idx_w),
        .l_idx(ctrl_l_idx_w)
    );

    cn_update_iams #(.Q(Q), .ROW_DEGREE(ROW_DEGREE)) iams_unit_A (
        .clk              (clk),
        .layer_idx        (layer_idx_A),
        .current_node_idx (4'd0),
        .vn_degree        (vn_degree_A),
        .vtc_mags_flat    (vtc_mags_A),
        .vtc_signs        (vtc_signs_A),
        .ctv_out          (ctv_out_A)
    );

    cn_update_iams #(.Q(Q), .ROW_DEGREE(ROW_DEGREE)) iams_unit_B (
        .clk              (clk),
        .layer_idx        (layer_idx_B),
        .current_node_idx (4'd0),
        .vn_degree        (vn_degree_B),
        .vtc_mags_flat    (vtc_mags_B),
        .vtc_signs        (vtc_signs_B),
        .ctv_out          (ctv_out_B)
    );

endmodule


// 2. SPLIT STORAGE UNIT
module split_storage_unit #(
    parameter Q           = 4,
    parameter MAX_ROW_DEG = 10
)(
    input  wire                          clk,
    input  wire                          write_en,
    input  wire [5:0]                    layer_addr,
    input  wire [Q-1:0]                  in_min1,
    input  wire [Q-1:0]                  in_min2,
    input  wire [5:0]                    in_idx1,
    input  wire [MAX_ROW_DEG-1:0]        in_signs,
    output wire [Q-1:0]                  out_min1,
    output wire [Q-1:0]                  out_min2,
    output wire [5:0]                    out_idx1,
    output wire [MAX_ROW_DEG-1:0]        out_signs
);
    localparam WIDTH = (2*Q) + 6 + MAX_ROW_DEG;
    reg [WIDTH-1:0] compressed_ram [0:41];

    always @(posedge clk) begin
        if (write_en)
            compressed_ram[layer_addr] <= {in_min1, in_min2, in_idx1, in_signs};
    end

    assign {out_min1, out_min2, out_idx1, out_signs} = compressed_ram[layer_addr];
endmodule


// 3. CTV MEMORY
module ctv_memory #(
    parameter Q           = 4,
    parameter Z           = 52,
    parameter L_COUNT     = 42,
    parameter MAX_ROW_DEG = 10
)(
    input  wire                  clk,
    input  wire                  write_en,
    input  wire [5:0]            layer_addr,
    input  wire [5:0]            vn_addr,
    input  wire signed [Q-1:0]   ctv_in,
    output wire signed [Q-1:0]   ctv_out
);
    // Flattened 2-D memory: index = layer_addr*Z + vn_addr
    reg signed [Q-1:0] ctv_ram [0:L_COUNT*Z-1];
    wire [11:0] addr;
    assign addr = {layer_addr, 6'b0} + {6'b0, vn_addr}; // layer*64 + vn (safe upper bound)

    always @(posedge clk) begin
        if (write_en)
            ctv_ram[addr] <= ctv_in;
    end

    assign ctv_out = ctv_ram[addr];
endmodule


// 4. SELECTIVE-SHIFT NETWORK
module selective_shift_network #(
    parameter Z = 52,
    parameter Q = 4
)(
    input  wire [Z*Q-1:0] data_in,
    input  wire [5:0]     shift_val,
    input  wire           is_nonzero_entry,
    output wire [Z*Q-1:0] data_out
);
    assign data_out = is_nonzero_entry ?
                      ((data_in << (shift_val * Q)) | (data_in >> ((Z - shift_val) * Q))) :
                      {(Z*Q){1'b0}};
endmodule


// 5. MERGED CONTROLLER
module ldpc_merged_controller #(
    parameter IT_MAX  = 15,
    parameter L_COUNT = 42
)(
    input  wire       clk,
    input  wire       reset,
    output reg        done,
    output wire [7:0] t_idx,
    output wire [5:0] l_idx
);
    reg [7:0] t_counter;
    reg [5:0] l_counter;

    always @(posedge clk) begin
        if (reset) begin
            t_counter <= 1;
            l_counter <= 0;
            done      <= 0;
        end else if (!done) begin
            if (l_counter < L_COUNT - 1) begin
                l_counter <= l_counter + 1;
            end else if (t_counter < IT_MAX) begin
                l_counter <= 0;
                t_counter <= t_counter + 1;
            end else begin
                done <= 1;
            end
        end
    end

    assign t_idx = t_counter;
    assign l_idx = l_counter;
endmodule


// 6. CN UPDATE (IAMS)
//    vtc_mags port changed from unpacked array to flat packed bus
//    Slice: mag[i] = vtc_mags_flat[ i*(Q-1) +: (Q-1) ]
module cn_update_iams #(
    parameter Q           = 4,
    parameter D_THRESHOLD = 6,
    parameter ROW_DEGREE  = 10
)(  input wire   clk,
    input  wire [5:0]                    layer_idx,
    input  wire [3:0]                    current_node_idx,
    input  wire [7:0]                    vn_degree,
    output wire signed [Q-1:0]           ctv_out,
    input  wire [ROW_DEGREE-1:0]         vtc_signs,
    // CHANGED: flat packed bus instead of unpacked array
    input  wire [ROW_DEGREE*(Q-1)-1:0]   vtc_mags_flat
);
    reg  [Q-2:0] min1, min2;
    reg  [3:0]   idx1, idx2;
    reg  [Q-2:0] mag_final;
    wire         total_sign, tau_sign;
    // ctv_out driven combinationally from mag_final and tau_sign
    wire [Q-1:0] mag_signed;
    assign mag_signed = tau_sign ? (~{1'b0,mag_final} + 1'b1) : {{1'b0}, mag_final};
    assign ctv_out    = mag_signed;

    // Unpack magnitudes from flat bus into local array for readability
    reg [Q-2:0] mags [0:ROW_DEGREE-1];
    integer i;
    always @(*) begin
        for (i = 0; i < ROW_DEGREE; i = i + 1)
            mags[i] = vtc_mags_flat[i*(Q-1) +: (Q-1)];
    end

    // Find min1, min2 and their indices
    always @(*) begin
        min1 = {(Q-1){1'b1}};
        min2 = {(Q-1){1'b1}};
        idx1 = 0;
        idx2 = 0;
        for (i = 0; i < ROW_DEGREE; i = i + 1) begin
            if (mags[i] < min1) begin
                min2 = min1; idx2 = idx1;
                min1 = mags[i]; idx1 = i[3:0];
            end else if (mags[i] < min2) begin
                min2 = mags[i]; idx2 = i[3:0];
            end
        end
    end

    assign total_sign = ^vtc_signs;
    assign tau_sign   = total_sign ^ vtc_signs[current_node_idx];

    // IAMS decision logic – fully combinational so mag_final is ready
    // in the same cycle as the inputs (Algorithm 1, Eq 5 / Eq 10)
    always @(*) begin
        if (layer_idx < 4 && vn_degree >= D_THRESHOLD) begin
            // Core check + high-degree VN: OMS offset lambda=1
            mag_final = (min1 > 1) ? (min1 - 1) : {(Q-1){1'b0}};
        end else begin
            if (current_node_idx == idx1)
                mag_final = min2;
            else if (current_node_idx == idx2)
                mag_final = min1;
            else if (min1 == min2)
                mag_final = (min1 > 0) ? (min1 - 1) : {(Q-1){1'b0}};
            else
                mag_final = min1;
        end
    end

endmodule


// 7. VN UPDATE
module vn_update #(
    parameter Q     = 4,
    parameter Q_APP = 6
)(
    input  wire                    clk,
    input  wire [Q_APP-1:0]        app_in,
    input  wire [7:0]              t_idx,
    input  wire [5:0]              layer_idx,
    input  wire [5:0]              vn_idx,
    input  wire signed [Q-1:0]     ctv_stored,
    output wire signed [Q-1:0]     vtc_new,
    output wire signed [Q_APP-1:0] beta_tilde
);
    wire signed [Q-1:0]     ctv_old;
    wire signed [Q_APP-1:0] sub_res;

    // First iteration: force old CTV = 0
    assign ctv_old  = (t_idx == 8'd1) ? {Q{1'b0}} : ctv_stored;

    // beta_tilde = app_in - ctv_old  (sign-extended)
    assign sub_res  = $signed(app_in) - {{(Q_APP-Q){ctv_old[Q-1]}}, ctv_old};
    assign beta_tilde = sub_res;

    // Clip to Q-bit alphabet {-2^(Q-1) .. 2^(Q-1)-1}
    assign vtc_new = (sub_res > $signed({{(Q_APP-Q){1'b0}},{1'b0},{(Q-1){1'b1}}}))
                         ? {1'b0,{(Q-1){1'b1}}}          // +7  for Q=4
                   : (sub_res < $signed({{(Q_APP-Q){1'b1}},{1'b1},{(Q-1){1'b0}}}))
                         ? {1'b1,{(Q-1){1'b0}}}          // -8  for Q=4
                   : sub_res[Q-1:0];
endmodule


// 8. APP UPDATE UNIT
module app_update_unit #(
    parameter Q     = 4,
    parameter Q_APP = 6
)(
    input  wire signed [Q-1:0]     alpha_curr,
    input  wire signed [Q_APP-1:0] beta_tilde,
    output reg  signed [Q_APP-1:0] app_new
);
    wire signed [Q_APP:0] full_sum;

    assign full_sum = {{(Q_APP-Q+1){alpha_curr[Q-1]}}, alpha_curr}
                    + {{1{beta_tilde[Q_APP-1]}}, beta_tilde};

    // Saturate to Q_APP-bit signed range
    always @(*) begin
        if (full_sum > $signed({{2{1'b0}},{(Q_APP-1){1'b1}}}) )  // > +31 for Q_APP=6
            app_new = {1'b0,{(Q_APP-1){1'b1}}};                  // +31
        else if (full_sum < $signed({{2{1'b1}},{(Q_APP-1){1'b0}}}))  // < -32 for Q_APP=6
            app_new = {1'b1,{(Q_APP-1){1'b0}}};                  // -32
        else
            app_new = full_sum[Q_APP-1:0];
    end
endmodule


// 9. TOP-LEVEL DECODER LAYER
//    channel_llr port changed from unpacked array to flat packed bus
//    Slice: llr[i] = channel_llr_flat[ i*Q_APP +: Q_APP ]
module ldpc_decoder_layer #(
    parameter Q          = 4,
    parameter Q_APP      = 6,
    parameter Z          = 52,
    parameter L_COUNT    = 42,
    parameter ROW_DEGREE = 10
)(
    input  wire                        clk,
    input  wire                        reset,
    // CHANGED: flat packed bus instead of unpacked array
    input  wire [Z*Q_APP-1:0]          channel_llr_flat,
    output reg  [Z-1:0]                decoded_bits,
    output reg                         done
);
    wire [7:0] t_idx;
    wire [5:0] l_idx;
    wire       ctrl_done;

    // APP memory (internal unpacked array – allowed inside module)
    reg  [Q_APP-1:0]        app_memory     [0:Z-1];
    reg  signed [Q-1:0]     ctv_mem_in_r   [0:ROW_DEGREE-1];
    wire signed [Q-1:0]     ctv_mem_out_w  [0:ROW_DEGREE-1];
    wire signed [Q-1:0]     vtc_messages   [0:ROW_DEGREE-1];
    wire signed [Q_APP-1:0] beta_tilde_vals[0:ROW_DEGREE-1];
    wire signed [Q-1:0]     ctv_messages   [0:ROW_DEGREE-1];
    wire signed [Q_APP-1:0] app_updated    [0:ROW_DEGREE-1];
    reg                     ctv_mem_we;

    // Controller
    ldpc_merged_controller #(.IT_MAX(15), .L_COUNT(L_COUNT)) controller (
        .clk   (clk),
        .reset (reset),
        .done  (ctrl_done),
        .t_idx (t_idx),
        .l_idx (l_idx)
    );

    // CTV memories
    genvar g;
    generate
        for (g = 0; g < ROW_DEGREE; g = g + 1) begin : ctv_mem_gen
            ctv_memory #(.Q(Q), .Z(Z), .L_COUNT(L_COUNT), .MAX_ROW_DEG(ROW_DEGREE))
            ctv_mem_inst (
                .clk        (clk),
                .write_en   (ctv_mem_we),
                .layer_addr (l_idx),
                .vn_addr    (g[5:0]),
                .ctv_in     (ctv_mem_in_r[g]),
                .ctv_out    (ctv_mem_out_w[g])
            );
        end
    endgenerate

    // VN update units
    generate
        for (g = 0; g < ROW_DEGREE; g = g + 1) begin : vn_update_gen
            vn_update #(.Q(Q), .Q_APP(Q_APP)) vn_update_inst (
                .clk        (clk),
                .app_in     (app_memory[g]),
                .t_idx      (t_idx),
                .layer_idx  (l_idx),
                .vn_idx     (g[5:0]),
                .ctv_stored (ctv_mem_out_w[g]),
                .vtc_new    (vtc_messages[g]),
                .beta_tilde (beta_tilde_vals[g])
            );
        end
    endgenerate

    // APP update units
    generate
        for (g = 0; g < ROW_DEGREE; g = g + 1) begin : app_update_gen
            app_update_unit #(.Q(Q), .Q_APP(Q_APP)) app_update_inst (
                .alpha_curr (ctv_messages[g]),
                .beta_tilde (beta_tilde_vals[g]),
                .app_new    (app_updated[g])
            );
        end
    endgenerate

    // Pack VTC messages into flat magnitude and sign buses for CNU input
    wire [ROW_DEGREE*(Q-1)-1:0] vtc_mags_flat;
    wire [ROW_DEGREE-1:0]       vtc_signs_flat;

    generate
        for (g = 0; g < ROW_DEGREE; g = g + 1) begin : vtc_pack
            // magnitude = absolute value of vtc_messages[g] (lower Q-1 bits when positive)
            // sign      = MSB of the signed vtc_messages[g]
            assign vtc_mags_flat[g*(Q-1) +: (Q-1)] =
                vtc_messages[g][Q-1] ? (~vtc_messages[g][Q-2:0] + 1'b1) : vtc_messages[g][Q-2:0];
            assign vtc_signs_flat[g] = vtc_messages[g][Q-1];
        end
    endgenerate

    // Instantiate one CNU per variable node in the row
    // Each CNU sees all ROW_DEGREE VTC messages and outputs the
    // CTV message for variable node g (current_node_idx = g).
    generate
        for (g = 0; g < ROW_DEGREE; g = g + 1) begin : cnu_gen
            cn_update_iams #(
                .Q          (Q),
                .ROW_DEGREE (ROW_DEGREE)
            ) cnu_inst (
                .clk              (clk),
                .layer_idx        (l_idx),
                .current_node_idx (g[3:0]),
                .vn_degree        (8'd10),       // baseline: treat degree = ROW_DEGREE
                .vtc_mags_flat    (vtc_mags_flat),
                .vtc_signs        (vtc_signs_flat),
                .ctv_out          (ctv_messages[g])
            );
        end
    endgenerate

    // Initialization and APP memory update
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < Z; i = i + 1)
                app_memory[i] <= channel_llr_flat[i*Q_APP +: Q_APP];
            ctv_mem_we <= 0;
            done       <= 0;
        end else begin
            for (i = 0; i < ROW_DEGREE; i = i + 1)
                app_memory[i] <= app_updated[i];
            ctv_mem_we <= 1;
            for (i = 0; i < ROW_DEGREE; i = i + 1)
                ctv_mem_in_r[i] <= ctv_messages[i];
            if (ctrl_done) begin
                done <= 1;
                for (i = 0; i < Z; i = i + 1)
                    decoded_bits[i] <= app_memory[i][Q_APP-1];
            end
        end
    end

endmodule
