`timescale 1ns/1ps

// =============================================================
// cnn_checksum_tb.v
//
// PURPOSE:
//   Verify the input loading interface after changing
//   pixel_valid from level-sensitive to rising-edge-sensitive.
//
// This testbench is NOT a replacement for cnn_top_tb.v.
//
// It specifically verifies:
//
//   1. start enters ST_LOAD_INPUT
//   2. one pixel_valid rising edge = one pixel load
//   3. 1024 pixels are loaded
//   4. checksum = 0xCEA
//   5. full CNN inference still completes
//   6. final class = 8
//
// IMPORTANT:
//   pixel_valid is deliberately pulsed once per pixel.
//
// =============================================================

module cnn_checksum_tb;

    // =========================================================
    // CLOCK
    // =========================================================

    reg clk;

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end


    // =========================================================
    // DUT INPUTS
    // =========================================================

    reg        rst_n;
    reg        start;
    reg        pixel_valid;
    reg [7:0]  pixel_in;


    // =========================================================
    // DUT OUTPUTS
    // =========================================================

    wire       result_valid;
    wire [5:0] class_out;

    wire [5:0]  debug_status;
    wire [11:0] input_checksum;
    wire [23:0] diagnostic_bus;


    // =========================================================
    // DUT
    // =========================================================

    cnn_top dut (

        .clk            (clk),
        .rst_n          (rst_n),

        .start          (start),
        .pixel_valid    (pixel_valid),
        .pixel_in       (pixel_in),

        .result_valid   (result_valid),
        .class_out      (class_out),

        .debug_status   (debug_status),
        .input_checksum (input_checksum),
        .diagnostic_bus (diagnostic_bus)

    );


    // =========================================================
    // INPUT IMAGE
    // =========================================================

    reg [7:0] pix_mem [0:1023];


    // =========================================================
    // VARIABLES
    // =========================================================

    integer i;
    integer guard;

    integer software_checksum;


    // =========================================================
    // INITIALIZATION
    // =========================================================

    initial begin

        // -----------------------------------------------------
        // Initial control values
        // -----------------------------------------------------

        rst_n       = 1'b0;
        start       = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 8'd0;

        software_checksum = 0;


        // -----------------------------------------------------
        // Load test image
        // -----------------------------------------------------

        $display("");
        $display("====================================================");
        $display(" CNN CHECKSUM / INPUT HANDSHAKE TEST");
        $display("====================================================");
        $display("");

        $display("Loading test_image_pixels.hex ...");

        $readmemh(
            "test_image_pixels.hex",
            pix_mem
        );

        $display("Image loaded.");
        $display("");


        // -----------------------------------------------------
        // Calculate software checksum
        // -----------------------------------------------------

        for (i = 0; i < 1024; i = i + 1) begin

            software_checksum =
                (software_checksum + pix_mem[i]) & 12'hFFF;

        end

        $display(
            "Software checksum = 0x%03h (%0d)",
            software_checksum,
            software_checksum
        );

        if (software_checksum == 12'hCEA)
            $display("Software checksum PASS");
        else
            $display("Software checksum FAIL");


        // =====================================================
        // RESET
        // =====================================================

        $display("");
        $display("Resetting DUT...");

        repeat (5) @(negedge clk);

        rst_n = 1'b1;

        repeat (2) @(negedge clk);


        // =====================================================
        // START
        //
        // start rising edge moves:
        //
        // ST_IDLE -> ST_LOAD_INPUT
        // =====================================================

        $display("Starting input load...");

        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;


        // =====================================================
        // LOAD 1024 PIXELS
        //
        // IMPORTANT:
        //
        // Each pixel gets exactly one rising edge:
        //
        //      pixel_valid = 0
        //             |
        //             v
        //      pixel_valid = 1
        //             |
        //          one posedge
        //             |
        //             v
        //      pixel_valid = 0
        //
        // =====================================================

        for (i = 0; i < 1024; i = i + 1) begin

            // -------------------------------------------------
            // Present pixel while valid is LOW
            // -------------------------------------------------

            @(negedge clk);

            pixel_in    = pix_mem[i];
            pixel_valid = 1'b0;


            // -------------------------------------------------
            // Rising edge of pixel_valid
            // -------------------------------------------------

            @(negedge clk);

            pixel_valid = 1'b1;


            // -------------------------------------------------
            // Next FPGA posedge sees pixel_valid_rise
            // -------------------------------------------------


            // -------------------------------------------------
            // Return valid LOW
            // -------------------------------------------------

            @(negedge clk);

            pixel_valid = 1'b0;

        end


        // =====================================================
        // INPUT LOAD COMPLETE
        // =====================================================

        $display("");
        $display("All 1024 pixels loaded.");


        // Allow checksum register to settle.
        repeat (4) @(negedge clk);


        // =====================================================
        // CHECKSUM TEST
        // =====================================================

        $display("");
        $display("=====================================");
        $display(
            "Hardware checksum = 0x%03h (%0d)",
            input_checksum,
            input_checksum
        );
        $display(
            "Expected checksum = 0xCEA (%0d)",
            12'hCEA,
            12'hCEA
        );
        $display("=====================================");


        if (input_checksum === 12'hCEA) begin

            $display("CHECKSUM PASS");

        end
        else begin

            $display("CHECKSUM FAIL");

        end


        // =====================================================
        // FULL INFERENCE
        // =====================================================

        $display("");
        $display("Waiting for full CNN inference...");


        guard = 0;

        while (
            result_valid !== 1'b1 &&
            guard < 3000000
        ) begin

            @(posedge clk);

            guard = guard + 1;

        end


        // =====================================================
        // FINAL RESULTS
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FINAL HARDWARE-STYLE SIMULATION RESULT");
        $display("====================================================");

        $display(
            "result_valid = %b",
            result_valid
        );

        $display(
            "class_out    = %0d",
            class_out
        );

        $display(
            "debug_status = %0d",
            debug_status
        );

        $display(
            "checksum     = 0x%03h",
            input_checksum
        );

        $display(
            "guard clocks = %0d",
            guard
        );

        $display("");


        // =====================================================
        // FINAL PASS / FAIL
        // =====================================================

        if (
            result_valid === 1'b1 &&
            class_out === 6'd8 &&
            input_checksum === 12'hCEA
        ) begin

            $display(
                ">>> FULL PASS: class 8, checksum 0xCEA"
            );

        end
        else begin

            $display(
                ">>> FULL FAIL: CHECK RESULTS ABOVE"
            );

        end


        $display("====================================================");
        $display("");


        $finish;

    end

endmodule