`timescale 1ns/1ps

// =============================================================
// dense_mac_q88.v  (SYNCHRONOUS-OPERAND / BRAM-FRIENDLY)
//
// CHANGE vs original:
//   Operands a_in / b_in are now expected to arrive ONE CYCLE
//   after their address is presented on `addr` (Block RAM read
//   latency). A one-cycle warm-up is added; arithmetic is
//   byte-for-byte identical to the original.
//
//   addr(k) presented in cycle T  ->  a_in/b_in for k valid in T+1.
// =============================================================

module dense_mac_q88 (

    input wire        clk,
    input wire        rst_n,

    input wire        start,
    input wire [11:0] length,

    input wire [15:0] a_in,          // UNSIGNED pixel/activation, valid T+1
    input wire signed [15:0] b_in,   // SIGNED kernel, valid T+1
    input wire signed [15:0] bias_in,

    output reg [11:0] addr,

    output reg busy,
    output reg done,

    output reg signed [15:0] dense_out
);

    localparam ST_IDLE = 2'd0;
    localparam ST_RUN  = 2'd1;
    localparam ST_DONE = 2'd2;

    reg [1:0] state;

    reg [11:0] length_reg;
    reg [11:0] n_acc;        // operands accumulated so far
    reg        opvalid;      // operand-valid pipeline flag

    reg signed [39:0] accumulator;

    // ---- arithmetic (IDENTICAL to original) ----
    wire signed [32:0] a_ext = {17'd0, a_in};
    wire signed [32:0] b_ext = {{17{b_in[15]}}, b_in};
    wire signed [65:0] product_full     = a_ext * b_ext;
    wire signed [65:0] product_q88_full = product_full >>> 8;
    wire signed [39:0] product_q88      = product_q88_full[39:0];
    wire signed [39:0] bias_ext         = {{24{bias_in[15]}}, bias_in};
    wire signed [39:0] final_sum        = accumulator + bias_ext;

    localparam signed [39:0] MAX_Q88 =  40'sd32767;
    localparam signed [39:0] MIN_Q88 = -40'sd32768;

    // ---- retained for TB visibility (harmless) ----
    reg mac_valid_in;
    reg mac_clr;

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            length_reg  <= 12'd0;
            n_acc       <= 12'd0;
            opvalid     <= 1'b0;
            addr        <= 12'd0;
            accumulator <= 40'sd0;
            busy        <= 1'b0;
            done        <= 1'b0;
            dense_out   <= 16'sd0;
            mac_valid_in<= 1'b0;
            mac_clr     <= 1'b0;
        end
        else begin
            done         <= 1'b0;
            mac_valid_in <= 1'b0;
            mac_clr      <= 1'b0;

            case (state)

                ST_IDLE: begin
                    busy    <= 1'b0;
                    opvalid <= 1'b0;
                    n_acc   <= 12'd0;
                    if (start) begin
                        length_reg  <= length;
                        addr        <= 12'd0;   // present operand 0
                        accumulator <= 40'sd0;
                        n_acc       <= 12'd0;
                        opvalid     <= 1'b0;    // operand 0 not valid yet
                        busy        <= 1'b1;
                        state       <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    busy    <= 1'b1;
                    opvalid <= 1'b1;            // operands valid from 2nd RUN cycle on

                    if (opvalid) begin
                        accumulator <= accumulator + product_q88;
                        mac_valid_in<= 1'b1;
                        if (n_acc == length_reg - 12'd1)
                            state <= ST_DONE;
                        n_acc <= n_acc + 12'd1;
                    end

                    if (addr < length_reg - 12'd1)
                        addr <= addr + 12'd1;   // prefetch next operand
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    if (final_sum > MAX_Q88)       dense_out <= 16'sh7FFF;
                    else if (final_sum < MIN_Q88)  dense_out <= 16'sh8000;
                    else                           dense_out <= final_sum[15:0];
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule