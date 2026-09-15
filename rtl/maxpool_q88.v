`timescale 1ns/1ps

// =============================================================
// maxpool_q88.v
//
// SYNCHRONOUS-READ / BRAM-FRIENDLY MAX POOL
//
// Reads the 2x2 pooling window one value at a time through one
// synchronous BRAM read port.
//
// Protocol:
//   rd_addr stable in cycle N
//   rd_data contains that memory value in cycle N+1
//
// Numerical operation is the same signed max of the four window
// values. Only the cycle count and memory interface are changed.
// =============================================================

module maxpool_q88 #(
    parameter integer CHANNELS = 16,
    parameter integer INPUT_H  = 30,
    parameter integer INPUT_W  = 30,
    parameter integer KERNEL   = 2,
    parameter integer STRIDE   = 2
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    output reg [13:0] rd_addr,
    input  wire signed [15:0] rd_data,

    output reg signed [15:0] pool_out,
    output reg [11:0] out_addr,
    output reg out_valid,

    output reg busy,
    output reg done
);

    localparam integer OUTPUT_H = INPUT_H / STRIDE;
    localparam integer OUTPUT_W = INPUT_W / STRIDE;

    localparam integer INPUT_CHANNEL_SIZE  = INPUT_H * INPUT_W;
    localparam integer OUTPUT_CHANNEL_SIZE = OUTPUT_H * OUTPUT_W;

    localparam ST_IDLE = 2'd0;
    localparam ST_RUN  = 2'd1;
    localparam ST_DONE = 2'd2;

    reg [1:0] state;

    reg [5:0] ch;
    reg [4:0] row;
    reg [4:0] col;

    // 0 = present a0
    // 1 = capture a0 / present a1
    // 2 = capture a1 / present a2
    // 3 = capture a2 / present a3
    // 4 = capture a3
    // 5 = emit result
    reg [2:0] s;

    reg signed [15:0] v0;
    reg signed [15:0] v1;
    reg signed [15:0] v2;
    reg signed [15:0] v3;

    // =========================================================
    // WINDOW BASE ADDRESS
    // =========================================================

    reg [13:0] base;

    always @(*) begin
        base =
            ch * INPUT_CHANNEL_SIZE +
            (row * STRIDE) * INPUT_W +
            (col * STRIDE);
    end

    // =========================================================
    // SYNCHRONOUS READ ADDRESS
    //
    // At each clock, the address presented here is sampled by the
    // BRAM read process in cnn_top. rd_data becomes valid one
    // clock later.
    // =========================================================

    always @(*) begin
        case (s)

            3'd0:
                rd_addr = base;

            3'd1:
                rd_addr = base + 14'd1;

            3'd2:
                rd_addr = base + INPUT_W;

            3'd3:
                rd_addr = base + INPUT_W + 14'd1;

            default:
                rd_addr = base;

        endcase
    end

    // =========================================================
    // SIGNED MAX
    // =========================================================

    reg signed [15:0] m01;
    reg signed [15:0] m23;
    reg signed [15:0] mfull;

    always @(*) begin

        m01 =
            (v1 > v0) ? v1 : v0;

        m23 =
            (v3 > v2) ? v3 : v2;

        mfull =
            (m23 > m01) ? m23 : m01;

    end

    // =========================================================
    // MAIN FSM
    // =========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            ch <= 6'd0;
            row <= 5'd0;
            col <= 5'd0;

            s <= 3'd0;

            pool_out <= 16'sd0;
            out_addr <= 12'd0;
            out_valid <= 1'b0;

            busy <= 1'b0;
            done <= 1'b0;

            v0 <= 16'sd0;
            v1 <= 16'sd0;
            v2 <= 16'sd0;
            v3 <= 16'sd0;

        end
        else begin

            out_valid <= 1'b0;
            done <= 1'b0;

            case (state)

                // =================================================
                // IDLE
                // =================================================

                ST_IDLE: begin

                    busy <= 1'b0;

                    if (start) begin

                        ch <= 6'd0;
                        row <= 5'd0;
                        col <= 5'd0;

                        s <= 3'd0;

                        busy <= 1'b1;

                        state <= ST_RUN;

                    end

                end

                // =================================================
                // RUN
                // =================================================

                ST_RUN: begin

                    busy <= 1'b1;

                    // ------------------------------------------------
                    // rd_data is the result of the address presented
                    // during the preceding cycle.
                    // ------------------------------------------------

                    case (s)

                        3'd1:
                            v0 <= rd_data;

                        3'd2:
                            v1 <= rd_data;

                        3'd3:
                            v2 <= rd_data;

                        3'd4:
                            v3 <= rd_data;

                        default: ;

                    endcase

                    // ------------------------------------------------
                    // After v3 has been captured, the following state
                    // emits the max. Because the captures use
                    // nonblocking assignments, mfull here sees all
                    // four values from the completed window.
                    // ------------------------------------------------

                    if (s == 3'd5) begin

                        pool_out <=
                            mfull;

                        out_addr <=
                            ch * OUTPUT_CHANNEL_SIZE +
                            row * OUTPUT_W +
                            col;

                        out_valid <=
                            1'b1;

                        s <=
                            3'd0;

                        // ---------------------------------------------
                        // Advance to next pooling window
                        // ---------------------------------------------

                        if (col == OUTPUT_W-1) begin

                            col <= 5'd0;

                            if (row == OUTPUT_H-1) begin

                                row <= 5'd0;

                                if (ch == CHANNELS-1) begin

                                    busy <= 1'b0;
                                    state <= ST_DONE;

                                end
                                else begin

                                    ch <=
                                        ch + 6'd1;

                                end

                            end
                            else begin

                                row <=
                                    row + 5'd1;

                            end

                        end
                        else begin

                            col <=
                                col + 5'd1;

                        end

                    end
                    else begin

                        s <=
                            s + 3'd1;

                    end

                end

                // =================================================
                // DONE
                // =================================================

                ST_DONE: begin

                    busy <= 1'b0;
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

                end

            endcase

        end

    end

endmodule
