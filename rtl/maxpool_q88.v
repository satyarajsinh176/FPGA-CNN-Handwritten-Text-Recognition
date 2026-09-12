`timescale 1ns/1ps

// =============================================================
// maxpool_q88.v
//
// 2x2 MAX POOL
//
// Input:
//     CHANNELS x INPUT_H x INPUT_W
//
// Pool:
//     2 x 2
//     stride 2
//
// For current network:
//
//     16 x 30 x 30
//
// Output:
//
//     16 x 15 x 15
//
// Layout:
//
//     CHW
//
// Output address:
//
//     channel*225 + row*15 + col
//
// IMPORTANT:
//
//     pool_out, out_addr and out_valid are produced together.
//     out_valid is the transaction-valid signal.
//
// =============================================================

module maxpool_q88 #(
    parameter integer CHANNELS = 16,
    parameter integer INPUT_H  = 30,
    parameter integer INPUT_W  = 30,
    parameter integer KERNEL   = 2,
    parameter integer STRIDE   = 2
)(
    input wire clk,
    input wire rst_n,
    input wire start,

    input wire signed [15:0] value_00,
    input wire signed [15:0] value_01,
    input wire signed [15:0] value_10,
    input wire signed [15:0] value_11,

    output reg [13:0] addr_00,
    output reg [13:0] addr_01,
    output reg [13:0] addr_10,
    output reg [13:0] addr_11,

    output reg signed [15:0] pool_out,
    output reg [11:0] out_addr,

    output reg out_valid,

    output reg busy,
    output reg done
);

    // =========================================================
    // GEOMETRY
    // =========================================================

    localparam integer OUTPUT_H =
        INPUT_H / STRIDE;

    localparam integer OUTPUT_W =
        INPUT_W / STRIDE;

    localparam integer INPUT_CHANNEL_SIZE =
        INPUT_H * INPUT_W;

    localparam integer OUTPUT_CHANNEL_SIZE =
        OUTPUT_H * OUTPUT_W;

    localparam integer TOTAL_OUTPUTS =
        CHANNELS * OUTPUT_CHANNEL_SIZE;


    // =========================================================
    // STATES
    // =========================================================

    localparam ST_IDLE = 2'd0;
    localparam ST_RUN  = 2'd1;
    localparam ST_DONE = 2'd2;

    reg [1:0] state;


    // =========================================================
    // COUNTERS
    // =========================================================

    reg [5:0] ch;
    reg [4:0] row;
    reg [4:0] col;


    // =========================================================
    // CURRENT WINDOW BASE ADDRESS
    // =========================================================

    integer base_addr;

    always @(*) begin

        base_addr =
            ch * INPUT_CHANNEL_SIZE
            +
            (row * STRIDE) * INPUT_W
            +
            (col * STRIDE);

    end


    // =========================================================
    // FOUR INPUT ADDRESSES
    //
    // The addresses are combinational from the current
    // channel / row / column.
    // =========================================================

    always @(*) begin

        addr_00 = base_addr;

        addr_01 = base_addr + 1;

        addr_10 = base_addr + INPUT_W;

        addr_11 = base_addr + INPUT_W + 1;

    end


    // =========================================================
    // MAXIMUM
    //
    // SIGNED Q8.8 COMPARISON
    // =========================================================

    reg signed [15:0] max_value;

    always @(*) begin

        max_value = value_00;

        if (value_01 > max_value)
            max_value = value_01;

        if (value_10 > max_value)
            max_value = value_10;

        if (value_11 > max_value)
            max_value = value_11;

    end


    // =========================================================
    // MAIN FSM
    // =========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            ch  <= 6'd0;
            row <= 5'd0;
            col <= 5'd0;

            pool_out <= 16'sd0;
            out_addr <= 12'd0;

            out_valid <= 1'b0;

            busy <= 1'b0;
            done <= 1'b0;

        end
        else begin

            // =================================================
            // DEFAULT PULSES
            // =================================================

            out_valid <= 1'b0;
            done      <= 1'b0;


            // =================================================
            // FSM
            // =================================================

            case (state)


                // =================================================
                // IDLE
                // =================================================

                ST_IDLE: begin

                    busy <= 1'b0;

                    if (start) begin

                        ch  <= 6'd0;
                        row <= 5'd0;
                        col <= 5'd0;

                        pool_out <= 16'sd0;
                        out_addr <= 12'd0;

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
                    // Produce ONE complete Pool1 transaction.
                    //
                    // At this clock edge:
                    //
                    //     pool_out
                    //     out_addr
                    //     out_valid
                    //
                    // all refer to the SAME window.
                    // ------------------------------------------------

                    pool_out <= max_value;

                    out_addr <=
                        ch * OUTPUT_CHANNEL_SIZE
                        +
                        row * OUTPUT_W
                        +
                        col;

                    out_valid <= 1'b1;


                    // ------------------------------------------------
                    // Advance column.
                    // ------------------------------------------------

                    if (col == OUTPUT_W - 1) begin

                        col <= 5'd0;


                        // ------------------------------------------------
                        // Advance row.
                        // ------------------------------------------------

                        if (row == OUTPUT_H - 1) begin

                            row <= 5'd0;


                            // ------------------------------------------------
                            // Advance channel.
                            // ------------------------------------------------

                            if (ch == CHANNELS - 1) begin

                                ch <= 6'd0;

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

                end

            endcase

        end

    end

endmodule