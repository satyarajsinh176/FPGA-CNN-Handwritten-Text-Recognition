// =============================================================
// mac_q88.v
// Q8.8 Multiply-Accumulate Unit
//
// Operation : accumulator += (a × b) >> 8
//
// Pipeline (2 stages, latency = 2 clock cycles):
//   Stage 1 : register inputs a, b, valid_in, clr
//   Stage 2 : signed 16×16 multiply → 32-bit product
//   Stage 3 : arithmetic shift >> 8, add to accumulator
//
// Ports:
//   clk       : 100 MHz clock
//   rst_n     : active-low synchronous reset
//   valid_in  : a and b are valid this cycle
//   clr       : 1 = start fresh accumulation (new neuron / new filter)
//               clr travels through pipeline with its data so the
//               accumulator is cleared exactly when the first product arrives
//   a [15:0]  : Q8.8 input activation (signed)
//   b [15:0]  : Q8.8 weight          (signed)
//   valid_out : accumulator has a new value this cycle
//   result    : 40-bit signed accumulator in Q8.8 units
//               (40 bits gives safe headroom for 1024 accumulated products)
//
// Q8.8 reminder:
//   integer value 256 = float 1.0
//   integer value -512 = float -2.0
//   multiply: (a_int × b_int) >> 8 gives result in same Q8.8 units
//
// FPGA mapping:
//   16×16 signed multiply in Stage 2 maps to one DSP48E1 on xc7z020
//   40-bit accumulator uses LUT/carry chain
// =============================================================

module mac_q88 (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              valid_in,
    input  wire              clr,
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    output reg               valid_out,
    output reg  signed [39:0] result
);

    // ---------------------------------------------------------
    // Stage 1 - register inputs
    // ---------------------------------------------------------
    reg signed [15:0] a_s1;
    reg signed [15:0] b_s1;
    reg               valid_s1;
    reg               clr_s1;

    always @(posedge clk) begin
        if (!rst_n) begin
            a_s1     <= 16'sd0;
            b_s1     <= 16'sd0;
            valid_s1 <= 1'b0;
            clr_s1   <= 1'b0;
        end else begin
            a_s1     <= a;
            b_s1     <= b;
            valid_s1 <= valid_in;
            clr_s1   <= clr;
        end
    end

    // ---------------------------------------------------------
    // Stage 2 - signed 16×16 multiply → 32-bit product
    // ---------------------------------------------------------
    reg signed [31:0] product_s2;
    reg               valid_s2;
    reg               clr_s2;

    always @(posedge clk) begin
        if (!rst_n) begin
            product_s2 <= 32'sd0;
            valid_s2   <= 1'b0;
            clr_s2     <= 1'b0;
        end else begin
            product_s2 <= a_s1 * b_s1;
            valid_s2   <= valid_s1;
            clr_s2     <= clr_s1;
        end
    end

    // ---------------------------------------------------------
    // Stage 3 - arithmetic shift >> 8 then accumulate
    //
    // product_s2 is Q16.16 (32-bit)
    // >>> 8 gives Q8.8 in 32-bit, sign preserved
    // sign-extend to 40 bits before adding to accumulator
    // ---------------------------------------------------------
    wire signed [31:0] shifted;
    assign shifted = product_s2 >>> 8;

    always @(posedge clk) begin
        if (!rst_n) begin
            result    <= 40'sd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_s2;

            if (valid_s2) begin
                if (clr_s2)
                    // New accumulation: load first product
                    // (clear previous sum)
                    result <= {{8{shifted[31]}}, shifted};
                else
                    // Continue accumulation
                    result <= result + {{8{shifted[31]}}, shifted};
            end
        end
    end

    // =========================================================
    // TEMPORARY DEBUG
    //
    // Shows the ACTUAL activation and weight that have entered
    // Stage 1 of the MAC.
    //
    // This does NOT change the MAC operation.
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && valid_s1) begin
            $display(
                "MAC_STAGE1 t=%0t A=%0d B=%0d CLR=%b",
                $time,
                $signed(a_s1),
                $signed(b_s1),
                clr_s1
            );
        end
    end

endmodule