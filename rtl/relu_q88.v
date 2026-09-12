`timescale 1ns/1ps

// =============================================================
// relu_q88.v
//
// Signed Q8.8 ReLU.
//
// negative -> 0
// non-negative -> unchanged
//
// =============================================================

module relu_q88 (

    input wire signed [15:0] in,

    output wire signed [15:0] out

);

    assign out =
        in[15] ? 16'sd0 : in;

endmodule