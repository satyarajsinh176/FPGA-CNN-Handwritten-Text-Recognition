`timescale 1ns/1ps

// =============================================================
// cnn_gpio_wrapper.v
//
// FINAL PYNQ-Z2 GPIO INTERFACE
//
// GPIO0:
//   Channel 1:
//      bit 0 = rst_n
//      bit 1 = start
//      bit 2 = pixel_valid
//
//   Channel 2:
//      bits [7:0] = pixel
//
// GPIO1:
//   Channel 1:
//      bit 0 = sticky result_valid
//
//   Channel 2:
//      [23:18] = class_out
//      [17:12] = debug_status
//      [11:0]  = input_checksum
//
// =============================================================

module cnn_gpio_wrapper (

    input  wire        clk,

    input  wire [2:0]  ctrl,
    input  wire [7:0]  pixel,

    output wire [0:0]  result_valid_bus,
    output wire [23:0] class_bus

);


    // =========================================================
    // CONTROL
    // =========================================================

    wire rst_n;
    wire start;
    wire pixel_valid;

    assign rst_n       = ctrl[0];
    assign start       = ctrl[1];
    assign pixel_valid = ctrl[2];


    // =========================================================
    // CNN OUTPUTS
    // =========================================================

    wire       result_valid;
    wire [5:0] class_out;

    wire [5:0]  debug_status;
    wire [11:0] input_checksum;
    wire [23:0] diagnostic_bus;


    // =========================================================
    // CNN
    // =========================================================

    cnn_top u_cnn (

        .clk            (clk),

        .rst_n          (rst_n),
        .start          (start),
        .pixel_valid    (pixel_valid),
        .pixel_in       (pixel),

        .result_valid   (result_valid),
        .class_out      (class_out),

        .debug_status   (debug_status),
        .input_checksum (input_checksum),
        .diagnostic_bus (diagnostic_bus)

    );


    // =========================================================
    // STICKY RESULT VALID
    //
    // result_valid from cnn_top is a pulse/state indication.
    //
    // The result is latched so Linux/Python does not need to
    // catch a single FPGA clock.
    //
    // A new START clears the previous result.
    // =========================================================

    reg result_valid_latched;


    always @(posedge clk) begin

        if (!rst_n) begin

            result_valid_latched <= 1'b0;

        end
        else begin

            // -------------------------------------------------
            // New inference starts.
            // Clear previous result.
            // -------------------------------------------------

            if (start) begin

                result_valid_latched <= 1'b0;

            end

            // -------------------------------------------------
            // New result available.
            // -------------------------------------------------

            else if (result_valid) begin

                result_valid_latched <= 1'b1;

            end

        end

    end


    // =========================================================
    // RESULT VALID
    // =========================================================

    assign result_valid_bus[0] =
        result_valid_latched;


    // =========================================================
    // OUTPUT STATUS BUS
    //
    // [23:18] = predicted class
    // [17:12] = CNN FSM debug status
    // [11:0]  = input checksum
    //
    // Total:
    //
    //     6 + 6 + 12 = 24 bits
    //
    // =========================================================

    assign class_bus = {

        class_out,
        debug_status,
        input_checksum

    };


endmodule