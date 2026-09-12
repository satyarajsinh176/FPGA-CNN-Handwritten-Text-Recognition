// =============================================================
// bram_weight_ctrl.v
//
// BRAM Weight Controller
//
// Dense1 is physically split into four 32K-entry BRAM banks
// to avoid the 17-bit RAMB36E1 address cascade / ADDR15 DRC.
//
// Logical Dense1 address:
//
//     addr[16:15] = bank
//     addr[14:0]  = address inside bank
//
// Mapping:
//
//     0       .. 32767   -> bank0
//     32768   .. 65535  -> bank1
//     65536   .. 98303  -> bank2
//     98304   .. 131071 -> bank3
//
// The logical Dense1 address seen by cnn_top is unchanged.
//
// All memory reads are registered with one clock cycle latency.
// =============================================================

module bram_weight_ctrl #(
    parameter HEX_DIR = "C:/fpga_cnn_accel/weights/fixed/"
)(
    input  wire              clk,
    input  wire              rst_n,

    input  wire [16:0]       addr,
    input  wire [2:0]        layer_sel,
    input  wire [6:0]        bias_addr,

    output reg signed [15:0] weight_out,
    output reg signed [15:0] bias_out
);

    // =========================================================
    // Layer selection
    // =========================================================

    localparam LAYER_CONV1  = 3'd0;
    localparam LAYER_CONV2  = 3'd1;
    localparam LAYER_CONV3  = 3'd2;
    localparam LAYER_DENSE1 = 3'd3;
    localparam LAYER_OUTPUT = 3'd4;


    // =========================================================
    // Kernel BRAMs
    // =========================================================

    // ---------------------------------------------------------
    // Conv1
    // ---------------------------------------------------------

    (* ram_style = "block" *)
    reg signed [15:0] bram_conv1_k [0:143];


    // ---------------------------------------------------------
    // Conv2
    // ---------------------------------------------------------

    (* ram_style = "block" *)
    reg signed [15:0] bram_conv2_k [0:4607];


    // ---------------------------------------------------------
    // Conv3
    // ---------------------------------------------------------

    (* ram_style = "block" *)
    reg signed [15:0] bram_conv3_k [0:18431];


    // =========================================================
    // Dense1
    //
    // Four independent 32768-entry memories.
    //
    // 32768 × 16-bit = 524288 bits per bank.
    //
    // Four banks together represent the original:
    //
    //     131072 × 16-bit
    // =========================================================

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k0 [0:32767];

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k1 [0:32767];

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k2 [0:32767];

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k3 [0:32767];


    // ---------------------------------------------------------
    // Output layer
    // ---------------------------------------------------------

    (* ram_style = "block" *)
    reg signed [15:0] bram_output_k [0:7935];


    // =========================================================
    // Bias arrays
    // =========================================================

    reg signed [15:0] bias_conv1  [0:15];
    reg signed [15:0] bias_conv2  [0:31];
    reg signed [15:0] bias_conv3  [0:63];
    reg signed [15:0] bias_dense1 [0:127];
    reg signed [15:0] bias_output [0:61];


    // =========================================================
    // MEMORY INITIALIZATION
    // =========================================================

    initial begin

        // -----------------------------------------------------
        // Convolution weights
        // -----------------------------------------------------

        $readmemh(
            {HEX_DIR, "conv1_kernel.hex"},
            bram_conv1_k
        );

        $readmemh(
            {HEX_DIR, "conv2_kernel.hex"},
            bram_conv2_k
        );

        $readmemh(
            {HEX_DIR, "conv3_kernel.hex"},
            bram_conv3_k
        );


        // -----------------------------------------------------
        // Dense1 bank weights
        // -----------------------------------------------------

        $readmemh(
            {HEX_DIR, "dense1_kernel_bank0.hex"},
            bram_dense1_k0
        );

        $readmemh(
            {HEX_DIR, "dense1_kernel_bank1.hex"},
            bram_dense1_k1
        );

        $readmemh(
            {HEX_DIR, "dense1_kernel_bank2.hex"},
            bram_dense1_k2
        );

        $readmemh(
            {HEX_DIR, "dense1_kernel_bank3.hex"},
            bram_dense1_k3
        );


        // -----------------------------------------------------
        // Output weights
        // -----------------------------------------------------

        $readmemh(
            {HEX_DIR, "output_kernel.hex"},
            bram_output_k
        );


        // -----------------------------------------------------
        // Biases
        // -----------------------------------------------------

        $readmemh(
            {HEX_DIR, "conv1_bias.hex"},
            bias_conv1
        );

        $readmemh(
            {HEX_DIR, "conv2_bias.hex"},
            bias_conv2
        );

        $readmemh(
            {HEX_DIR, "conv3_bias.hex"},
            bias_conv3
        );

        $readmemh(
            {HEX_DIR, "dense1_bias.hex"},
            bias_dense1
        );

        $readmemh(
            {HEX_DIR, "output_bias.hex"},
            bias_output
        );

    end


    // =========================================================
    // REGISTERED LAYER SELECT
    // =========================================================

    reg [2:0] layer_sel_q;

    always @(posedge clk) begin
        layer_sel_q <= layer_sel;
    end


    // =========================================================
    // REGISTERED KERNEL OUTPUTS
    // =========================================================

    reg signed [15:0] conv1_k_q;
    reg signed [15:0] conv2_k_q;
    reg signed [15:0] conv3_k_q;
    reg signed [15:0] output_k_q;


    // =========================================================
    // DENSE1 BANK OUTPUT REGISTERS
    // =========================================================
    //
    // Each bank has its own independent registered read.
    //
    // IMPORTANT:
    //   These outputs are one cycle behind the incoming address.
    //   Therefore the bank select must also be registered so
    //   that bank selection and BRAM data refer to the SAME
    //   logical address.
    // =========================================================

    reg signed [15:0] dense1_k0_q;
    reg signed [15:0] dense1_k1_q;
    reg signed [15:0] dense1_k2_q;
    reg signed [15:0] dense1_k3_q;

    // Registered bank selection.
    // This is the key fix.
    reg [1:0] dense1_bank_q;


    // =========================================================
    // REGISTERED BIAS OUTPUTS
    // =========================================================

    reg signed [15:0] conv1_b_q;
    reg signed [15:0] conv2_b_q;
    reg signed [15:0] conv3_b_q;
    reg signed [15:0] dense1_b_q;
    reg signed [15:0] output_b_q;


    // =========================================================
    // CONV1 BRAM READ
    // =========================================================

    always @(posedge clk) begin
        conv1_k_q <= bram_conv1_k[addr[7:0]];
    end


    // =========================================================
    // CONV2 BRAM READ
    // =========================================================

    always @(posedge clk) begin
        conv2_k_q <= bram_conv2_k[addr[12:0]];
    end


    // =========================================================
    // CONV3 BRAM READ
    // =========================================================

    always @(posedge clk) begin
        conv3_k_q <= bram_conv3_k[addr[14:0]];
    end


    // =========================================================
    // DENSE1 BANK 0 BRAM READ
    //
    // Logical addresses:
    //     0 .. 32767
    //
    // Physical address:
    //     addr[14:0]
    // =========================================================

    always @(posedge clk) begin
        dense1_k0_q <= bram_dense1_k0[addr[14:0]];
    end


    // =========================================================
    // DENSE1 BANK 1 BRAM READ
    //
    // Logical addresses:
    //     32768 .. 65535
    // =========================================================

    always @(posedge clk) begin
        dense1_k1_q <= bram_dense1_k1[addr[14:0]];
    end


    // =========================================================
    // DENSE1 BANK 2 BRAM READ
    //
    // Logical addresses:
    //     65536 .. 98303
    // =========================================================

    always @(posedge clk) begin
        dense1_k2_q <= bram_dense1_k2[addr[14:0]];
    end


    // =========================================================
    // DENSE1 BANK 3 BRAM READ
    //
    // Logical addresses:
    //     98304 .. 131071
    // =========================================================

    always @(posedge clk) begin
        dense1_k3_q <= bram_dense1_k3[addr[14:0]];
    end


    // =========================================================
    // DENSE1 BANK SELECT REGISTER
    //
    // addr[16:15] is registered on the SAME clock edge as the
    // BRAM reads above.
    //
    // Therefore:
    //
    //   dense1_bank_q
    //       and
    //   dense1_k*_q
    //
    // both correspond to the SAME incoming logical address.
    // =========================================================

    always @(posedge clk) begin
        dense1_bank_q <= addr[16:15];
    end


    // =========================================================
    // OUTPUT BRAM READ
    // =========================================================

    always @(posedge clk) begin
        output_k_q <= bram_output_k[addr[12:0]];
    end


    // =========================================================
    // BIAS READS
    // =========================================================

    always @(posedge clk) begin
        conv1_b_q <= bias_conv1[bias_addr[3:0]];
    end


    always @(posedge clk) begin
        conv2_b_q <= bias_conv2[bias_addr[4:0]];
    end


    always @(posedge clk) begin
        conv3_b_q <= bias_conv3[bias_addr[5:0]];
    end


    always @(posedge clk) begin
        dense1_b_q <= bias_dense1[bias_addr[6:0]];
    end


    always @(posedge clk) begin
        output_b_q <= bias_output[bias_addr[5:0]];
    end


    // =========================================================
    // DENSE1 BANK SELECTION
    //
    // IMPORTANT:
    //   Use dense1_bank_q, NOT addr[16:15].
    //
    //   dense1_bank_q is delayed to match the registered BRAM
    //   outputs.
    // =========================================================

    reg signed [15:0] dense1_selected_q;

    always @(*) begin

        case (dense1_bank_q)

            2'b00:
                dense1_selected_q = dense1_k0_q;

            2'b01:
                dense1_selected_q = dense1_k1_q;

            2'b10:
                dense1_selected_q = dense1_k2_q;

            2'b11:
                dense1_selected_q = dense1_k3_q;

            default:
                dense1_selected_q = 16'sd0;

        endcase

    end


    // =========================================================
    // FINAL WEIGHT OUTPUT
    // =========================================================

    always @(*) begin

        case (layer_sel_q)

            LAYER_CONV1:
                weight_out = conv1_k_q;

            LAYER_CONV2:
                weight_out = conv2_k_q;

            LAYER_CONV3:
                weight_out = conv3_k_q;

            LAYER_DENSE1:
                weight_out = dense1_selected_q;

            LAYER_OUTPUT:
                weight_out = output_k_q;

            default:
                weight_out = 16'sd0;

        endcase


        case (layer_sel_q)

            LAYER_CONV1:
                bias_out = conv1_b_q;

            LAYER_CONV2:
                bias_out = conv2_b_q;

            LAYER_CONV3:
                bias_out = conv3_b_q;

            LAYER_DENSE1:
                bias_out = dense1_b_q;

            LAYER_OUTPUT:
                bias_out = output_b_q;

            default:
                bias_out = 16'sd0;

        endcase

    end

endmodule