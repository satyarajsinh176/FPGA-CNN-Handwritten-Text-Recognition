`timescale 1ns/1ps

// =============================================================
// cnn_top.v
//
// FPGA CNN Character Recognition
//
// Pipeline:
//
//   Input       32x32x1
//       |
//   Conv1       16x30x30
//       |
//   Pool1       16x15x15
//       |
//   Conv2       32x13x13
//       |
//   Pool2       32x6x6
//       |
//   Conv3       64x4x4
//       |
//   Flatten     1024
//       |
//   Dense1      128   (ReLU)
//       |
//   Output      62    (NO ReLU)
//       |
//   Argmax
//
// =============================================================

module cnn_top (

    input wire        clk,
    input wire        rst_n,

    input wire        start,
    input wire        pixel_valid,
    input wire [7:0]  pixel_in,

    output reg        result_valid,
    output reg [5:0]  class_out,

    output wire [5:0]  debug_status,
    output wire [11:0] input_checksum,
    output wire [23:0] diagnostic_bus

);


    // =========================================================
    // FSM STATES
    // =========================================================

    localparam ST_IDLE       = 4'd0;
    localparam ST_LOAD_INPUT = 4'd1;
    localparam ST_CONV1      = 4'd2;
    localparam ST_POOL1      = 4'd3;
    localparam ST_CONV2      = 4'd4;
    localparam ST_POOL2      = 4'd5;
    localparam ST_CONV3      = 4'd6;
    localparam ST_DENSE1     = 4'd7;
    localparam ST_OUTPUT     = 4'd8;
    localparam ST_DEBUG      = 4'd10;


    reg [3:0] state;


    // =========================================================
    // GEOMETRY
    // =========================================================

    localparam C1_IN_W       = 32;
    localparam C1_OUT_W      = 30;
    localparam C1_COUT       = 16;
    localparam C1_OUT_SIZE   = 900;

    localparam C2_OUT_W      = 13;
    localparam C2_COUT       = 32;
    localparam C2_OUT_SIZE   = 169;
    localparam C2_KERNEL_SIZE = 144;

    localparam C3_OUT_W      = 4;
    localparam C3_COUT       = 64;
    localparam C3_OUT_SIZE   = 16;
    localparam C3_KERNEL_SIZE = 288;

    localparam D1_INPUTS     = 1024;
    localparam D1_OUTPUTS    = 128;

    localparam OUT_INPUTS    = 128;
    localparam OUT_CLASSES   = 62;


    // =========================================================
    // MEMORIES
    // =========================================================

    reg [15:0] input_bram [0:1023];

    reg signed [15:0] act_bram_a [0:14399];

    reg signed [15:0] act_bram_b [0:14399];

    reg signed [15:0] pool1_bram [0:3599];

    reg signed [15:0] act2_bram [0:5407];

    reg signed [15:0] pool2_bram [0:1151];

    reg signed [15:0] dense1_bram [0:127];

    reg signed [15:0] output_bram [0:61];


    // =========================================================
    // WEIGHT CONTROLLER
    // =========================================================

    localparam LAYER_CONV1  = 3'd0;
    localparam LAYER_CONV2  = 3'd1;
    localparam LAYER_CONV3  = 3'd2;
    localparam LAYER_DENSE1 = 3'd3;
    localparam LAYER_OUTPUT = 3'd4;


    reg [16:0] w_addr;
    reg [2:0]  w_layer_sel;
    reg [6:0]  w_bias_addr;

    wire signed [15:0] w_weight_out;
    wire signed [15:0] w_bias_out;


    bram_weight_ctrl weight_ctrl (

        .clk        (clk),
        .rst_n      (rst_n),

        .addr       (w_addr),
        .layer_sel  (w_layer_sel),

        .bias_addr  (w_bias_addr),

        .weight_out (w_weight_out),
        .bias_out   (w_bias_out)

    );


    // =========================================================
    // CONV1 ENGINE
    // =========================================================

    reg        ce_start;
    reg [11:0] ce_length;

    reg [15:0] ce_a_in;
    reg signed [15:0] ce_b_in;
    reg signed [15:0] ce_bias_in;

    wire [11:0] ce_addr;
    wire        ce_busy;
    wire        ce_done;
    wire signed [15:0] ce_out;


    conv_engine_q88 conv_engine (

        .clk      (clk),
        .rst_n    (rst_n),

        .start    (ce_start),
        .length   (ce_length),

        .a_in     (ce_a_in),
        .b_in     (ce_b_in),
        .bias_in  (ce_bias_in),

        .addr     (ce_addr),

        .busy     (ce_busy),
        .done     (ce_done),

        .conv_out (ce_out)

    );


    reg [9:0] out_row;
    reg [9:0] out_col;
    reg [6:0] out_ch;


    always @(*) begin

        ce_a_in =
            input_bram[
                (out_row + (ce_addr / 12'd3)) *
                C1_IN_W +
                (out_col + (ce_addr % 12'd3))
            ];

        ce_b_in =
            weight_ctrl.bram_conv1_k[
                out_ch * 9 +
                ce_addr
            ];

        ce_bias_in =
            weight_ctrl.bias_conv1[out_ch];

    end


    // =========================================================
    // POOL1
    // =========================================================

    reg pool_start;

    wire [13:0] pool_addr_00;
    wire [13:0] pool_addr_01;
    wire [13:0] pool_addr_10;
    wire [13:0] pool_addr_11;

    wire signed [15:0] pool_value_00;
    wire signed [15:0] pool_value_01;
    wire signed [15:0] pool_value_10;
    wire signed [15:0] pool_value_11;

    wire signed [15:0] pool_out;
    wire [11:0] pool_out_addr;
    wire pool_out_valid;
    wire pool_busy;
    wire pool_done;


    assign pool_value_00 =
        act_bram_b[pool_addr_00];

    assign pool_value_01 =
        act_bram_b[pool_addr_01];

    assign pool_value_10 =
        act_bram_b[pool_addr_10];

    assign pool_value_11 =
        act_bram_b[pool_addr_11];


    maxpool_q88 #(
        .CHANNELS (16),
        .INPUT_H  (30),
        .INPUT_W  (30),
        .KERNEL   (2),
        .STRIDE   (2)
    ) pool1_engine (

        .clk       (clk),
        .rst_n     (rst_n),
        .start     (pool_start),

        .value_00  (pool_value_00),
        .value_01  (pool_value_01),
        .value_10  (pool_value_10),
        .value_11  (pool_value_11),

        .addr_00   (pool_addr_00),
        .addr_01   (pool_addr_01),
        .addr_10   (pool_addr_10),
        .addr_11   (pool_addr_11),

        .pool_out  (pool_out),
        .out_addr  (pool_out_addr),
        .out_valid (pool_out_valid),

        .busy      (pool_busy),
        .done      (pool_done)

    );


    // =========================================================
    // CONV2 ENGINE
    // =========================================================

    reg        c2_start;
    reg [11:0] c2_length;

    reg [15:0] c2_a_in;
    reg signed [15:0] c2_b_in;
    reg signed [15:0] c2_bias_in;

    wire [11:0] c2_addr;
    wire        c2_busy;
    wire        c2_done;
    wire signed [15:0] c2_out;


    conv_engine_q88 conv2_engine (

        .clk      (clk),
        .rst_n    (rst_n),

        .start    (c2_start),
        .length   (c2_length),

        .a_in     (c2_a_in),
        .b_in     (c2_b_in),
        .bias_in  (c2_bias_in),

        .addr     (c2_addr),

        .busy     (c2_busy),
        .done     (c2_done),

        .conv_out (c2_out)

    );


    reg [4:0] c2_out_row;
    reg [4:0] c2_out_col;
    reg [5:0] c2_out_ch;

    integer c2_ic;
    integer c2_k;
    integer c2_ky;
    integer c2_kx;

    integer c2_input_index;
    integer c2_weight_index;


    always @(*) begin

        c2_ic = c2_addr / 12'd9;

        c2_k = c2_addr % 12'd9;

        c2_ky = c2_k / 3;

        c2_kx = c2_k % 3;


        c2_input_index =
            c2_ic * 225 +
            (c2_out_row + c2_ky) * 15 +
            (c2_out_col + c2_kx);


        c2_weight_index =
            c2_out_ch * C2_KERNEL_SIZE +
            c2_ic * 9 +
            c2_k;


        c2_a_in =
            pool1_bram[c2_input_index];

        c2_b_in =
            weight_ctrl.bram_conv2_k[c2_weight_index];

        c2_bias_in =
            weight_ctrl.bias_conv2[c2_out_ch];

    end


    // =========================================================
    // POOL2
    // =========================================================

    reg pool2_start;

    wire [13:0] pool2_addr_00;
    wire [13:0] pool2_addr_01;
    wire [13:0] pool2_addr_10;
    wire [13:0] pool2_addr_11;

    wire signed [15:0] pool2_value_00;
    wire signed [15:0] pool2_value_01;
    wire signed [15:0] pool2_value_10;
    wire signed [15:0] pool2_value_11;

    wire signed [15:0] pool2_out;
    wire [11:0] pool2_out_addr;
    wire pool2_out_valid;
    wire pool2_busy;
    wire pool2_done;


    assign pool2_value_00 =
        act2_bram[pool2_addr_00];

    assign pool2_value_01 =
        act2_bram[pool2_addr_01];

    assign pool2_value_10 =
        act2_bram[pool2_addr_10];

    assign pool2_value_11 =
        act2_bram[pool2_addr_11];


    maxpool_q88 #(
        .CHANNELS (32),
        .INPUT_H  (13),
        .INPUT_W  (13),
        .KERNEL   (2),
        .STRIDE   (2)
    ) pool2_engine (

        .clk       (clk),
        .rst_n     (rst_n),
        .start     (pool2_start),

        .value_00  (pool2_value_00),
        .value_01  (pool2_value_01),
        .value_10  (pool2_value_10),
        .value_11  (pool2_value_11),

        .addr_00   (pool2_addr_00),
        .addr_01   (pool2_addr_01),
        .addr_10   (pool2_addr_10),
        .addr_11   (pool2_addr_11),

        .pool_out  (pool2_out),
        .out_addr  (pool2_out_addr),
        .out_valid (pool2_out_valid),

        .busy      (pool2_busy),
        .done      (pool2_done)

    );


    // =========================================================
    // CONV3 ENGINE
    // =========================================================

    reg        c3_start;
    reg [11:0] c3_length;

    reg [15:0] c3_a_in;
    reg signed [15:0] c3_b_in;
    reg signed [15:0] c3_bias_in;

    wire [11:0] c3_addr;
    wire        c3_busy;
    wire        c3_done;
    wire signed [15:0] c3_out;


    conv_engine_q88 conv3_engine (

        .clk      (clk),
        .rst_n    (rst_n),

        .start    (c3_start),
        .length   (c3_length),

        .a_in     (c3_a_in),
        .b_in     (c3_b_in),
        .bias_in  (c3_bias_in),

        .addr     (c3_addr),

        .busy     (c3_busy),
        .done     (c3_done),

        .conv_out (c3_out)

    );


    reg [2:0] c3_out_row;
    reg [2:0] c3_out_col;
    reg [5:0] c3_out_ch;

    integer c3_ic;
    integer c3_k;
    integer c3_ky;
    integer c3_kx;

    integer c3_input_index;
    integer c3_weight_index;


    always @(*) begin

        c3_ic = c3_addr / 12'd9;

        c3_k = c3_addr % 12'd9;

        c3_ky = c3_k / 3;

        c3_kx = c3_k % 3;


        c3_input_index =
            c3_ic * 36 +
            (c3_out_row + c3_ky) * 6 +
            (c3_out_col + c3_kx);


        c3_weight_index =
            c3_out_ch * C3_KERNEL_SIZE +
            c3_ic * 9 +
            c3_k;


        c3_a_in =
            pool2_bram[c3_input_index];

        c3_b_in =
            weight_ctrl.bram_conv3_k[c3_weight_index];

        c3_bias_in =
            weight_ctrl.bias_conv3[c3_out_ch];

    end


    // =========================================================
    // DENSE1 ENGINE
    // =========================================================

    reg        d1_start;
    reg [11:0] d1_length;

    reg [15:0] d1_a_in;
    reg signed [15:0] d1_b_in;
    reg signed [15:0] d1_bias_in;

    wire [11:0] d1_addr;
    wire        d1_busy;
    wire        d1_done;
    wire signed [15:0] d1_out;


    conv_engine_q88 dense1_engine (

        .clk      (clk),
        .rst_n    (rst_n),

        .start    (d1_start),
        .length   (d1_length),

        .a_in     (d1_a_in),
        .b_in     (d1_b_in),
        .bias_in  (d1_bias_in),

        .addr     (d1_addr),

        .busy     (d1_busy),
        .done     (d1_done),

        .conv_out (d1_out)

    );


    reg [6:0] d1_out_neuron;

    integer d1_weight_index;


    always @(*) begin

        d1_a_in =
            act_bram_a[d1_addr];


        d1_weight_index =
            d1_out_neuron * D1_INPUTS +
            d1_addr;


        case (d1_weight_index[16:15])

            2'b00:
                d1_b_in =
                    weight_ctrl.bram_dense1_k0[
                        d1_weight_index[14:0]
                    ];

            2'b01:
                d1_b_in =
                    weight_ctrl.bram_dense1_k1[
                        d1_weight_index[14:0]
                    ];

            2'b10:
                d1_b_in =
                    weight_ctrl.bram_dense1_k2[
                        d1_weight_index[14:0]
                    ];

            2'b11:
                d1_b_in =
                    weight_ctrl.bram_dense1_k3[
                        d1_weight_index[14:0]
                    ];

            default:
                d1_b_in = 16'sd0;

        endcase


        d1_bias_in =
            weight_ctrl.bias_dense1[d1_out_neuron];

    end


    // =========================================================
    // OUTPUT LAYER
    //
    // 128 INPUTS -> 62 CLASSES
    //
    // IMPORTANT:
    //
    // NO ReLU HERE.
    //
    // conv_engine_q88 cannot be used because it contains
    // dense_mac_q88 followed by relu_q88.
    //
    // Therefore this layer has its own sequential MAC.
    //
    // =========================================================

    reg        out_start;
    reg [11:0] out_length;

    reg [15:0] out_a_in;
    reg signed [15:0] out_b_in;
    reg signed [15:0] out_bias_in;

    reg [6:0] out_mac_index;

    reg signed [39:0] out_acc;

    reg signed [39:0] out_product;

    reg signed [39:0] out_acc_next;

    reg signed [39:0] out_final_acc;

    reg signed [15:0] out_value;

    reg out_busy;
    reg out_done;


    integer output_weight_index;


    // =========================================================
    // OUTPUT INPUT / WEIGHT / BIAS
    // =========================================================

    always @(*) begin

        // Dense1 output is signed Q8.8.
        out_a_in =
            dense1_bram[out_mac_index];


        // Output weight layout:
        //
        // class * 128 + input
        //
        output_weight_index =
            output_class * OUT_INPUTS +
            out_mac_index;


        out_b_in =
            weight_ctrl.bram_output_k[
                output_weight_index
            ];


        out_bias_in =
            weight_ctrl.bias_output[
                output_class
            ];

    end


    // =========================================================
    // OUTPUT PRODUCT
    //
    // Q8.8 × Q8.8
    //
    // Product is shifted right by 8.
    // =========================================================

    always @(*) begin

        out_product =
            (
                $signed(out_a_in) *
                $signed(out_b_in)
            ) >>> 8;

    end


    // =========================================================
    // ACCUMULATOR NEXT VALUE
    // =========================================================

    always @(*) begin

        out_acc_next =
            out_acc +
            out_product;

    end


    // =========================================================
    // FINAL ACCUMULATOR
    //
    // Last MAC + bias.
    // =========================================================

    always @(*) begin

        out_final_acc =
            out_acc_next +
            $signed(out_bias_in);

    end


    // =========================================================
    // OUTPUT MAC SEQUENTIAL ENGINE
    // =========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            out_mac_index <=
                7'd0;

            out_acc <=
                40'sd0;

            out_value <=
                16'sd0;

            out_busy <=
                1'b0;

            out_done <=
                1'b0;

        end
        else begin

            // -------------------------------------------------
            // done is a one-clock pulse
            // -------------------------------------------------

            out_done <=
                1'b0;


            // -------------------------------------------------
            // Start a new output class
            // -------------------------------------------------

            if (
                out_start &&
                !out_busy
            ) begin

                out_mac_index <=
                    7'd0;

                out_acc <=
                    40'sd0;

                out_busy <=
                    1'b1;

            end


            // -------------------------------------------------
            // One MAC per clock
            // -------------------------------------------------

            else if (out_busy) begin

                // ---------------------------------------------
                // Final input: index 127
                // ---------------------------------------------

                if (
                    out_mac_index == 7'd127
                ) begin

                    // Saturation
                    if (
                        out_final_acc >
                        40'sd32767
                    ) begin

                        out_value <=
                            16'sh7fff;

                    end
                    else if (
                        out_final_acc <
                        -40'sd32768
                    ) begin

                        out_value <=
                            16'sh8000;

                    end
                    else begin

                        out_value <=
                            out_final_acc[15:0];

                    end


                    out_acc <=
                        out_final_acc;


                    out_busy <=
                        1'b0;

                    out_done <=
                        1'b1;

                end

                // ---------------------------------------------
                // Normal MAC
                // ---------------------------------------------

                else begin

                    out_acc <=
                        out_acc_next;

                    out_mac_index <=
                        out_mac_index + 7'd1;

                end

            end

        end

    end


    // =========================================================
    // OUTPUT CLASS
    // =========================================================

    reg [5:0] output_class;


    // =========================================================
    // ARGMAX
    // =========================================================

    reg signed [15:0] best_value;

    reg [5:0] best_class;


    // =========================================================
    // DEBUG
    // =========================================================

    reg [13:0] debug_index;


    // =========================================================
    // INPUT CHECKSUM
    // =========================================================

    reg [11:0] input_checksum_reg;


    assign input_checksum =
        input_checksum_reg;


    // =========================================================
    // START EDGE DETECTOR
    // =========================================================

    reg start_d;

    wire start_rise;


    assign start_rise =
        start & ~start_d;


    // =========================================================
    // DEBUG STATUS
    // =========================================================

    assign debug_status = {
        2'b00,
        state
    };


    // =========================================================
    // DIAGNOSTIC BUS
    //
    // [23:8] = current output value
    // [7:0]  = debug index
    // =========================================================

    assign diagnostic_bus = {
        out_value,
        debug_index[7:0]
    };


    // =========================================================
    // MAIN FSM
    // =========================================================

    integer load_idx;


    always @(posedge clk) begin

        if (!rst_n) begin

            // -------------------------------------------------
            // FSM
            // -------------------------------------------------

            state <=
                ST_IDLE;


            // -------------------------------------------------
            // Outputs
            // -------------------------------------------------

            result_valid <=
                1'b0;

            class_out <=
                6'd0;


            // -------------------------------------------------
            // Input
            // -------------------------------------------------

            load_idx <=
                10'd0;

            input_checksum_reg <=
                12'd0;


            // -------------------------------------------------
            // Conv1 counters
            // -------------------------------------------------

            out_row <=
                10'd0;

            out_col <=
                10'd0;

            out_ch <=
                7'd0;


            // -------------------------------------------------
            // Conv2 counters
            // -------------------------------------------------

            c2_out_row <=
                5'd0;

            c2_out_col <=
                5'd0;

            c2_out_ch <=
                6'd0;


            // -------------------------------------------------
            // Conv3 counters
            // -------------------------------------------------

            c3_out_row <=
                3'd0;

            c3_out_col <=
                3'd0;

            c3_out_ch <=
                6'd0;


            // -------------------------------------------------
            // Dense1
            // -------------------------------------------------

            d1_out_neuron <=
                7'd0;


            // -------------------------------------------------
            // Output
            // -------------------------------------------------

            output_class <=
                6'd0;

            best_value <=
                -16'sd32768;

            best_class <=
                6'd0;


            // -------------------------------------------------
            // Debug
            // -------------------------------------------------

            debug_index <=
                14'd0;


            // -------------------------------------------------
            // Start
            // -------------------------------------------------

            start_d <=
                1'b0;


            // -------------------------------------------------
            // Engine control
            // -------------------------------------------------

            ce_start <=
                1'b0;

            ce_length <=
                12'd9;


            pool_start <=
                1'b0;


            c2_start <=
                1'b0;

            c2_length <=
                12'd144;


            pool2_start <=
                1'b0;


            c3_start <=
                1'b0;

            c3_length <=
                12'd288;


            d1_start <=
                1'b0;

            d1_length <=
                12'd1024;


            out_start <=
                1'b0;

            out_length <=
                12'd128;


            // -------------------------------------------------
            // Weight controller
            // -------------------------------------------------

            w_addr <=
                17'd0;

            w_layer_sel <=
                LAYER_CONV1;

            w_bias_addr <=
                7'd0;

        end
        else begin

            // =================================================
            // DEFAULT PULSES
            // =================================================

            start_d <=
                start;


            result_valid <=
                1'b0;


            ce_start <=
                1'b0;

            pool_start <=
                1'b0;

            c2_start <=
                1'b0;

            pool2_start <=
                1'b0;

            c3_start <=
                1'b0;

            d1_start <=
                1'b0;

            out_start <=
                1'b0;


            // =================================================
            // WEIGHT CONTROLLER DIAGNOSTIC ADDRESS
            // =================================================

            if (state == ST_CONV1) begin

                w_addr <=
                    out_ch * 17'd9 +
                    ce_addr;

                w_layer_sel <=
                    LAYER_CONV1;

                w_bias_addr <=
                    out_ch;

            end
            else if (state == ST_CONV2) begin

                w_addr <=
                    c2_out_ch * 17'd144 +
                    c2_addr;

                w_layer_sel <=
                    LAYER_CONV2;

                w_bias_addr <=
                    c2_out_ch;

            end
            else if (state == ST_CONV3) begin

                w_addr <=
                    c3_out_ch * 17'd288 +
                    c3_addr;

                w_layer_sel <=
                    LAYER_CONV3;

                w_bias_addr <=
                    c3_out_ch;

            end
            else if (state == ST_DENSE1) begin

                w_addr <=
                    d1_weight_index[16:0];

                w_layer_sel <=
                    LAYER_DENSE1;

                w_bias_addr <=
                    d1_out_neuron;

            end
            else if (state == ST_OUTPUT) begin

                w_addr <=
                    output_weight_index[16:0];

                w_layer_sel <=
                    LAYER_OUTPUT;

                w_bias_addr <=
                    output_class;

            end
            else begin

                w_addr <=
                    17'd0;

                w_layer_sel <=
                    LAYER_CONV1;

                w_bias_addr <=
                    7'd0;

            end


            // =================================================
            // FSM
            // =================================================

            case (state)


                // =================================================
                // IDLE
                // =================================================

                ST_IDLE: begin

                    if (start_rise) begin

                        load_idx <=
                            10'd0;

                        input_checksum_reg <=
                            12'd0;


                        out_row <=
                            10'd0;

                        out_col <=
                            10'd0;

                        out_ch <=
                            7'd0;


                        c2_out_row <=
                            5'd0;

                        c2_out_col <=
                            5'd0;

                        c2_out_ch <=
                            6'd0;


                        c3_out_row <=
                            3'd0;

                        c3_out_col <=
                            3'd0;

                        c3_out_ch <=
                            6'd0;


                        d1_out_neuron <=
                            7'd0;


                        output_class <=
                            6'd0;

                        best_value <=
                            -16'sd32768;

                        best_class <=
                            6'd0;


                        debug_index <=
                            14'd0;


                        state <=
                            ST_LOAD_INPUT;

                    end

                end


                // =================================================
                // LOAD INPUT
                // =================================================

                ST_LOAD_INPUT: begin

                    if (pixel_valid) begin

                        input_bram[load_idx] <=
                            {pixel_in,8'd0};


                        input_checksum_reg <=
                            input_checksum_reg +
                            {4'd0,pixel_in};


                        if (load_idx == 10'd1023) begin

                            load_idx <=
                                10'd0;


                            out_row <=
                                10'd0;

                            out_col <=
                                10'd0;

                            out_ch <=
                                7'd0;


                            state <=
                                ST_CONV1;

                        end
                        else begin

                            load_idx <=
                                load_idx + 10'd1;

                        end

                    end

                end


                // =================================================
                // CONV1
                // =================================================

                ST_CONV1: begin

                    ce_length <=
                        12'd9;


                    if (
                        !ce_busy &&
                        !ce_done
                    ) begin

                        ce_start <=
                            1'b1;

                    end


                    if (ce_done) begin

                        act_bram_b[
                            out_ch * C1_OUT_SIZE +
                            out_row * C1_OUT_W +
                            out_col
                        ] <=
                            ce_out;


                        if (
                            out_ch ==
                            C1_COUT - 1
                        ) begin

                            out_ch <=
                                7'd0;


                            if (
                                out_col ==
                                C1_OUT_W - 1
                            ) begin

                                out_col <=
                                    10'd0;


                                if (
                                    out_row ==
                                    C1_OUT_W - 1
                                ) begin

                                    out_row <=
                                        10'd0;

                                    out_col <=
                                        10'd0;

                                    out_ch <=
                                        7'd0;


                                    state <=
                                        ST_POOL1;

                                end
                                else begin

                                    out_row <=
                                        out_row + 10'd1;

                                end

                            end
                            else begin

                                out_col <=
                                    out_col + 10'd1;

                            end

                        end
                        else begin

                            out_ch <=
                                out_ch + 7'd1;

                        end

                    end

                end


                // =================================================
                // POOL1
                // =================================================

                ST_POOL1: begin

                    if (pool_out_valid) begin

                        pool1_bram[
                            pool_out_addr
                        ] <=
                            pool_out;

                    end


                    if (
                        !pool_busy &&
                        !pool_done
                    ) begin

                        pool_start <=
                            1'b1;

                    end


                    if (pool_done) begin

                        c2_out_row <=
                            5'd0;

                        c2_out_col <=
                            5'd0;

                        c2_out_ch <=
                            6'd0;


                        state <=
                            ST_CONV2;

                    end

                end


                // =================================================
                // CONV2
                // =================================================

                ST_CONV2: begin

                    c2_length <=
                        12'd144;


                    if (
                        !c2_busy &&
                        !c2_done
                    ) begin

                        c2_start <=
                            1'b1;

                    end


                    if (c2_done) begin

                        act2_bram[
                            c2_out_ch * C2_OUT_SIZE +
                            c2_out_row * C2_OUT_W +
                            c2_out_col
                        ] <=
                            c2_out;


                        if (
                            c2_out_ch ==
                            C2_COUT - 1
                        ) begin

                            c2_out_ch <=
                                6'd0;


                            if (
                                c2_out_col ==
                                C2_OUT_W - 1
                            ) begin

                                c2_out_col <=
                                    5'd0;


                                if (
                                    c2_out_row ==
                                    C2_OUT_W - 1
                                ) begin

                                    c2_out_row <=
                                        5'd0;

                                    c2_out_col <=
                                        5'd0;

                                    c2_out_ch <=
                                        6'd0;


                                    state <=
                                        ST_POOL2;

                                end
                                else begin

                                    c2_out_row <=
                                        c2_out_row + 5'd1;

                                end

                            end
                            else begin

                                c2_out_col <=
                                    c2_out_col + 5'd1;

                            end

                        end
                        else begin

                            c2_out_ch <=
                                c2_out_ch + 6'd1;

                        end

                    end

                end


                // =================================================
                // POOL2
                // =================================================

                ST_POOL2: begin

                    if (pool2_out_valid) begin

                        pool2_bram[
                            pool2_out_addr
                        ] <=
                            pool2_out;

                    end


                    if (
                        !pool2_busy &&
                        !pool2_done
                    ) begin

                        pool2_start <=
                            1'b1;

                    end


                    if (pool2_done) begin

                        c3_out_row <=
                            3'd0;

                        c3_out_col <=
                            3'd0;

                        c3_out_ch <=
                            6'd0;


                        state <=
                            ST_CONV3;

                    end

                end


                // =================================================
                // CONV3
                // =================================================

                ST_CONV3: begin

                    c3_length <=
                        12'd288;


                    if (
                        !c3_busy &&
                        !c3_done
                    ) begin

                        c3_start <=
                            1'b1;

                    end


                    if (c3_done) begin

                        act_bram_a[
                            c3_out_ch * C3_OUT_SIZE +
                            c3_out_row * C3_OUT_W +
                            c3_out_col
                        ] <=
                            c3_out;


                        if (
                            c3_out_ch ==
                            C3_COUT - 1
                        ) begin

                            c3_out_ch <=
                                6'd0;


                            if (
                                c3_out_col ==
                                C3_OUT_W - 1
                            ) begin

                                c3_out_col <=
                                    3'd0;


                                if (
                                    c3_out_row ==
                                    C3_OUT_W - 1
                                ) begin

                                    c3_out_row <=
                                        3'd0;

                                    c3_out_col <=
                                        3'd0;

                                    c3_out_ch <=
                                        6'd0;


                                    d1_out_neuron <=
                                        7'd0;


                                    state <=
                                        ST_DENSE1;

                                end
                                else begin

                                    c3_out_row <=
                                        c3_out_row + 3'd1;

                                end

                            end
                            else begin

                                c3_out_col <=
                                    c3_out_col + 3'd1;

                            end

                        end
                        else begin

                            c3_out_ch <=
                                c3_out_ch + 6'd1;

                        end

                    end

                end


                // =================================================
                // DENSE1
                // =================================================

                ST_DENSE1: begin

                    d1_length <=
                        12'd1024;


                    if (
                        !d1_busy &&
                        !d1_done
                    ) begin

                        d1_start <=
                            1'b1;

                    end


                    if (d1_done) begin

                        dense1_bram[
                            d1_out_neuron
                        ] <=
                            d1_out;


                        if (
                            d1_out_neuron ==
                            D1_OUTPUTS - 1
                        ) begin

                            d1_out_neuron <=
                                7'd0;


                            output_class <=
                                6'd0;


                            best_value <=
                                -16'sd32768;

                            best_class <=
                                6'd0;


                            state <=
                                ST_OUTPUT;

                        end
                        else begin

                            d1_out_neuron <=
                                d1_out_neuron + 7'd1;

                        end

                    end

                end


                // =================================================
                // OUTPUT
                // =================================================

                ST_OUTPUT: begin

                    out_length <=
                        12'd128;


                    // -------------------------------------------------
                    // Start current class
                    // -------------------------------------------------

                    if (!out_busy) begin

                        out_start <=
                            1'b1;

                    end


                    // -------------------------------------------------
                    // Current class finished
                    // -------------------------------------------------

                    if (out_done) begin

                        output_bram[
                            output_class
                        ] <=
                            out_value;


                        // ---------------------------------------------
                        // ARGMAX
                        // ---------------------------------------------

                        if (
                            out_value >
                            best_value
                        ) begin

                            best_value <=
                                out_value;

                            best_class <=
                                output_class;

                        end


                        // ---------------------------------------------
                        // Last class
                        // ---------------------------------------------

                        if (
                            output_class ==
                            OUT_CLASSES - 1
                        ) begin

                            if (
                                out_value >
                                best_value
                            ) begin

                                class_out <=
                                    output_class;

                            end
                            else begin

                                class_out <=
                                    best_class;

                            end


                            result_valid <=
                                1'b1;


                            debug_index <=
                                14'd0;


                            state <=
                                ST_DEBUG;

                        end
                        else begin

                            output_class <=
                                output_class + 6'd1;

                        end

                    end

                end


                // =================================================
                // DEBUG
                // =================================================

                ST_DEBUG: begin

                    result_valid <=
                        1'b1;

                end


                // =================================================
                // DEFAULT
                // =================================================

                default: begin

                    state <=
                        ST_IDLE;

                end

            endcase

        end

    end

endmodule