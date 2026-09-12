`timescale 1ns/1ps

// =============================================================
// dense_mac_q88.v
//
// DETERMINISTIC Q8.8 MAC ENGINE
//
// A:
//     UNSIGNED 16-bit Q8.8 image pixel.
//
// B:
//     SIGNED 16-bit Q8.8 kernel.
//
// Bias:
//     SIGNED 16-bit Q8.8.
//
// Exactly ONE multiplication is consumed per clock.
//
// For Conv1 length=9:
//
//     k=0
//     k=1
//     k=2
//     k=3
//     k=4
//     k=5
//     k=6
//     k=7
//     k=8
//
// No pipelined-valid ambiguity.
// No duplicated final transaction.
//
// =============================================================

module dense_mac_q88 (

    input wire        clk,
    input wire        rst_n,

    input wire        start,
    input wire [11:0] length,

    // ---------------------------------------------------------
    // IMPORTANT:
    //
    // A is UNSIGNED.
    //
    // Pixel 255 becomes:
    //
    //     255 << 8 = 65280 = 0xFF00
    //
    // This must NOT be interpreted as -256.
    // ---------------------------------------------------------

    input wire [15:0] a_in,

    // Signed kernel.
    input wire signed [15:0] b_in,

    // Signed bias.
    input wire signed [15:0] bias_in,

    output reg [11:0] addr,

    output reg busy,
    output reg done,

    output reg signed [15:0] dense_out

);


    // =========================================================
    // STATES
    // =========================================================

    localparam ST_IDLE = 2'd0;
    localparam ST_RUN  = 2'd1;
    localparam ST_DONE = 2'd2;

    reg [1:0] state;


    // =========================================================
    // CONTROL
    // =========================================================

    reg [11:0] length_reg;

    reg [11:0] count;


    // =========================================================
    // ACCUMULATOR
    // =========================================================

    reg signed [39:0] accumulator;


    // =========================================================
    // SIGNED EXTENSIONS
    // =========================================================

    // ---------------------------------------------------------
    // A:
    //
    // Zero extend because image pixel is unsigned.
    //
    // 0xFF00 remains +65280.
    // ---------------------------------------------------------

    wire signed [32:0] a_ext;

    assign a_ext =
        {17'd0, a_in};


    // ---------------------------------------------------------
    // B:
    //
    // Sign extend kernel.
    // ---------------------------------------------------------

    wire signed [32:0] b_ext;

    assign b_ext =
        {{17{b_in[15]}}, b_in};


    // =========================================================
    // FULL PRECISION PRODUCT
    // =========================================================

    wire signed [65:0] product_full;

    assign product_full =
        a_ext * b_ext;


    // =========================================================
    // Q8.8 RESTORATION
    //
    // Q8.8 × Q8.8
    //
    // Product has 16 fractional bits.
    //
    // Shift right by 8:
    //
    //     Q16.16 -> Q8.8
    //
    // =========================================================

    wire signed [65:0] product_q88_full;

    assign product_q88_full =
        product_full >>> 8;


    // =========================================================
    // 40-BIT PRODUCT
    // =========================================================

    wire signed [39:0] product_q88;

    assign product_q88 =
        product_q88_full[39:0];


    // =========================================================
    // BIAS EXTENSION
    // =========================================================

    wire signed [39:0] bias_ext;

    assign bias_ext =
        {{24{bias_in[15]}}, bias_in};


    // =========================================================
    // FINAL SUM
    // =========================================================

    wire signed [39:0] final_sum;

    assign final_sum =
        accumulator + bias_ext;


    // =========================================================
    // SATURATION LIMITS
    // =========================================================

    localparam signed [39:0] MAX_Q88 =
        40'sd32767;

    localparam signed [39:0] MIN_Q88 =
        -40'sd32768;


    // =========================================================
    // DEBUG-COMPATIBILITY SIGNALS
    //
    // Retained for existing testbench visibility.
    // =========================================================

    reg mac_valid_in;
    reg mac_clr;


    // =========================================================
    // MAIN FSM
    // =========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            length_reg <= 12'd0;

            count <= 12'd0;

            addr <= 12'd0;

            accumulator <= 40'sd0;

            busy <= 1'b0;

            done <= 1'b0;

            dense_out <= 16'sd0;

            mac_valid_in <= 1'b0;

            mac_clr <= 1'b0;

        end
        else begin

            // -------------------------------------------------
            // Defaults
            // -------------------------------------------------

            done <= 1'b0;

            mac_valid_in <= 1'b0;

            mac_clr <= 1'b0;


            case (state)


                // =================================================
                // IDLE
                // =================================================

                ST_IDLE: begin

                    busy <= 1'b0;

                    addr <= 12'd0;


                    if (start) begin

                        length_reg <=
                            length;

                        count <=
                            12'd0;

                        addr <=
                            12'd0;

                        accumulator <=
                            40'sd0;

                        busy <=
                            1'b1;

                        state <=
                            ST_RUN;

                    end

                end


                // =================================================
                // RUN
                // =================================================

                ST_RUN: begin

                    busy <= 1'b1;


                    // ------------------------------------------------
                    // Current A/B pair is consumed EXACTLY ONCE.
                    // ------------------------------------------------

                    mac_valid_in <= 1'b1;


                    // ------------------------------------------------
                    // First MAC.
                    // ------------------------------------------------

                    if (count == 12'd0) begin

                        mac_clr <= 1'b1;

                    end


                    // ------------------------------------------------
                    // Q8.8 MAC
                    // ------------------------------------------------

                    accumulator <=
                        accumulator +
                        product_q88;


                    // ------------------------------------------------
                    // Last MAC?
                    // ------------------------------------------------

                    if (count ==
                        (length_reg - 12'd1)) begin

                        state <=
                            ST_DONE;

                    end
                    else begin

                        count <=
                            count + 12'd1;

                        addr <=
                            count + 12'd1;

                    end

                end


                // =================================================
                // DONE
                // =================================================

                ST_DONE: begin

                    busy <= 1'b0;

                    mac_valid_in <= 1'b0;


                    // ------------------------------------------------
                    // Add bias AFTER all MAC terms are accumulated.
                    // ------------------------------------------------

                    if (final_sum > MAX_Q88) begin

                        dense_out <=
                            16'sh7FFF;

                    end
                    else if (final_sum < MIN_Q88) begin

                        dense_out <=
                            16'sh8000;

                    end
                    else begin

                        dense_out <=
                            final_sum[15:0];

                    end


                    done <= 1'b1;

                    state <= ST_IDLE;

                end


                // =================================================
                // DEFAULT
                // =================================================

                default: begin

                    state <= ST_IDLE;

                    busy <= 1'b0;

                    done <= 1'b0;

                    mac_valid_in <= 1'b0;

                    mac_clr <= 1'b0;

                end

            endcase

        end

    end

endmodule