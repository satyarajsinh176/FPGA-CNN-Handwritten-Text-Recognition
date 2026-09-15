`timescale 1ns/1ps

// =============================================================
// bram_weight_ctrl.v
//
// CNN WEIGHT / BIAS BRAM CONTROLLER
//
// Layer selection:
//
//   0 = Conv1
//   1 = Conv2
//   2 = Conv3
//   3 = Dense1
//   4 = Output
//
// IMPORTANT:
//
// All kernel memories are read synchronously.
//
// The requested address is sampled on a clock edge.
// The corresponding *_q register becomes valid after that edge.
//
// Dense1 is physically divided into four independent 32768-entry
// memories:
//
//   logical 0       .. 32767   -> bank 0
//   logical 32768   .. 65535   -> bank 1
//   logical 65536   .. 98303   -> bank 2
//   logical 98304   .. 131071 -> bank 3
//
// The logical 17-bit address seen by cnn_top does not change.
//
// cnn_top never accesses the internal memories directly.
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
    // LAYER SELECT
    // =========================================================

    localparam LAYER_CONV1  = 3'd0;
    localparam LAYER_CONV2  = 3'd1;
    localparam LAYER_CONV3  = 3'd2;
    localparam LAYER_DENSE1 = 3'd3;
    localparam LAYER_OUTPUT = 3'd4;


    // =========================================================
    // CONV1 KERNEL
    //
    // 16 output channels
    // 1 input channel
    // 3x3 kernel
    //
    // 16 * 9 = 144
    // =========================================================

    (* ram_style = "block" *)
    reg signed [15:0] bram_conv1_k [0:143];


    // =========================================================
    // CONV2 KERNEL
    //
    // 32 output channels
    // 16 input channels
    // 3x3 kernel
    //
    // 32 * 16 * 9 = 4608
    // =========================================================

    (* ram_style = "block" *)
    reg signed [15:0] bram_conv2_k [0:4607];


    // =========================================================
    // CONV3 KERNEL
    //
    // 64 output channels
    // 32 input channels
    // 3x3 kernel
    //
    // 64 * 32 * 9 = 18432
    // =========================================================

    (* ram_style = "block" *)
    reg signed [15:0] bram_conv3_k [0:18431];


    // =========================================================
    // DENSE1 KERNEL
    //
    // 128 neurons
    // 1024 inputs
    //
    // 128 * 1024 = 131072
    //
    // Split into four 32768-entry BRAMs.
    // =========================================================

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k0 [0:32767];

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k1 [0:32767];

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k2 [0:32767];

    (* ram_style = "block" *)
    reg signed [15:0] bram_dense1_k3 [0:32767];


    // =========================================================
    // OUTPUT KERNEL
    //
    // 62 classes
    // 128 inputs
    //
    // 62 * 128 = 7936
    // =========================================================

    (* ram_style = "block" *)
    reg signed [15:0] bram_output_k [0:7935];


    // =========================================================
    // BIAS MEMORIES
    // =========================================================

    reg signed [15:0] bias_conv1  [0:15];

    reg signed [15:0] bias_conv2  [0:31];

    reg signed [15:0] bias_conv3  [0:63];

    reg signed [15:0] bias_dense1 [0:127];

    reg signed [15:0] bias_output [0:61];


    // =========================================================
    // REGISTERED KERNEL OUTPUTS
    // =========================================================

    reg signed [15:0] conv1_k_q;

    reg signed [15:0] conv2_k_q;

    reg signed [15:0] conv3_k_q;


    reg signed [15:0] dense1_k0_q;

    reg signed [15:0] dense1_k1_q;

    reg signed [15:0] dense1_k2_q;

    reg signed [15:0] dense1_k3_q;


    reg signed [15:0] output_k_q;


    // =========================================================
    // REGISTERED BIAS OUTPUTS
    // =========================================================

    reg signed [15:0] conv1_b_q;

    reg signed [15:0] conv2_b_q;

    reg signed [15:0] conv3_b_q;

    reg signed [15:0] dense1_b_q;

    reg signed [15:0] output_b_q;


    // =========================================================
    // DENSE1 BANK REGISTER
    // =========================================================

    reg [1:0] dense1_bank_q;


    // =========================================================
    // MEMORY INITIALIZATION
    //
    // IMPORTANT:
    //
    // The four Dense1 bank files must contain the four already
    // permuted sections of dense1_kernel.hex.
    //
    // These files are:
    //
    //   dense1_kernel_bank0.hex
    //   dense1_kernel_bank1.hex
    //   dense1_kernel_bank2.hex
    //   dense1_kernel_bank3.hex
    //
    // The project documentation confirms these bank files are
    // part of the intended hardware organization.
    // =========================================================

    initial begin

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


        $readmemh(
            {HEX_DIR, "output_kernel.hex"},
            bram_output_k
        );


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
    // SYNCHRONOUS MEMORY READ
    // =========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            conv1_k_q <= 16'sd0;

            conv2_k_q <= 16'sd0;

            conv3_k_q <= 16'sd0;


            dense1_k0_q <= 16'sd0;

            dense1_k1_q <= 16'sd0;

            dense1_k2_q <= 16'sd0;

            dense1_k3_q <= 16'sd0;


            output_k_q <= 16'sd0;


            conv1_b_q <= 16'sd0;

            conv2_b_q <= 16'sd0;

            conv3_b_q <= 16'sd0;

            dense1_b_q <= 16'sd0;

            output_b_q <= 16'sd0;


            dense1_bank_q <= 2'd0;

        end
        else begin

            // -------------------------------------------------
            // Conv1
            // -------------------------------------------------

            conv1_k_q <=
                bram_conv1_k[
                    addr[7:0]
                ];


            // -------------------------------------------------
            // Conv2
            // -------------------------------------------------

            conv2_k_q <=
                bram_conv2_k[
                    addr[12:0]
                ];


            // -------------------------------------------------
            // Conv3
            // -------------------------------------------------

            conv3_k_q <=
                bram_conv3_k[
                    addr[14:0]
                ];


            // -------------------------------------------------
            // Dense1
            // -------------------------------------------------

            dense1_k0_q <=
                bram_dense1_k0[
                    addr[14:0]
                ];

            dense1_k1_q <=
                bram_dense1_k1[
                    addr[14:0]
                ];

            dense1_k2_q <=
                bram_dense1_k2[
                    addr[14:0]
                ];

            dense1_k3_q <=
                bram_dense1_k3[
                    addr[14:0]
                ];


            dense1_bank_q <=
                addr[16:15];


            // -------------------------------------------------
            // Output
            // -------------------------------------------------

            output_k_q <=
                bram_output_k[
                    addr[12:0]
                ];


            // -------------------------------------------------
            // Bias
            // -------------------------------------------------

            conv1_b_q <=
                bias_conv1[
                    bias_addr[3:0]
                ];

            conv2_b_q <=
                bias_conv2[
                    bias_addr[4:0]
                ];

            conv3_b_q <=
                bias_conv3[
                    bias_addr[5:0]
                ];

            dense1_b_q <=
                bias_dense1[
                    bias_addr[6:0]
                ];

            output_b_q <=
                bias_output[
                    bias_addr[5:0]
                ];

        end

    end


    // =========================================================
    // FINAL OUTPUT MUX
    //
    // NOTE:
    //
    // layer_sel is intentionally used directly here.
    //
    // The memory registers above have already been updated at
    // the clock edge. Therefore after that edge the selected
    // *_q value corresponds to the requested layer/address.
    //
    // This avoids introducing a second unwanted layer-selection
    // delay.
    // =========================================================

    always @(*) begin

        weight_out = 16'sd0;

        bias_out   = 16'sd0;


        case (layer_sel)

            LAYER_CONV1: begin

                weight_out =
                    conv1_k_q;

                bias_out =
                    conv1_b_q;

            end


            LAYER_CONV2: begin

                weight_out =
                    conv2_k_q;

                bias_out =
                    conv2_b_q;

            end


            LAYER_CONV3: begin

                weight_out =
                    conv3_k_q;

                bias_out =
                    conv3_b_q;

            end


            LAYER_DENSE1: begin

                case (dense1_bank_q)

                    2'd0:
                        weight_out =
                            dense1_k0_q;

                    2'd1:
                        weight_out =
                            dense1_k1_q;

                    2'd2:
                        weight_out =
                            dense1_k2_q;

                    2'd3:
                        weight_out =
                            dense1_k3_q;

                    default:
                        weight_out =
                            16'sd0;

                endcase


                bias_out =
                    dense1_b_q;

            end


            LAYER_OUTPUT: begin

                weight_out =
                    output_k_q;

                bias_out =
                    output_b_q;

            end


            default: begin

                weight_out =
                    16'sd0;

                bias_out =
                    16'sd0;

            end

        endcase

    end

endmodule