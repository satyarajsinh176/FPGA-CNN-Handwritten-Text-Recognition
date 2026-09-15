`timescale 1ns/1ps

// =============================================================
// conv_engine_q88.v
//
// Deterministic Conv/Dense engine wrapper.
//
// Input A:
//     UNSIGNED Q8.8 image value.
//
// Input B:
//     SIGNED Q8.8 kernel value.
//
// Bias:
//     SIGNED Q8.8.
//
// The actual accumulation is performed by dense_mac_q88.
//
// =============================================================

module conv_engine_q88 (

    input wire        clk,
    input wire        rst_n,

    input wire        start,

    input wire [11:0] length,

    input wire [15:0] a_in,

    input wire signed [15:0] b_in,

    input wire signed [15:0] bias_in,

    output wire [11:0] addr,

    output wire busy,
    output wire done,

    output wire signed [15:0] conv_out

);


    wire signed [15:0] mac_out;


    // =========================================================
    // DETERMINISTIC MAC ENGINE
    // =========================================================

    dense_mac_q88 mac_engine (

        .clk       (clk),
        .rst_n     (rst_n),

        .start     (start),
        .length    (length),

        .a_in      (a_in),
        .b_in      (b_in),
        .bias_in   (bias_in),

        .addr      (addr),

        .busy      (busy),
        .done      (done),

        .dense_out (mac_out)

    );


    // =========================================================
    // ReLU
    // =========================================================

    relu_q88 relu_inst (

        .in  (mac_out),
        .out (conv_out)

    );

endmodule