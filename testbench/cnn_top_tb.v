`timescale 1ns/1ps

// =============================================================
// cnn_top_tb.v
//
// FULL CNN RTL VERIFICATION
//
// Conv1   : 14400
// Pool1   : 3600
// Conv2   : 5408
// Pool2   : 1152
// Conv3   : 1024
// Dense1  : 128
// Output  : 62
//
// =============================================================

module cnn_top_tb;


    // =========================================================
    // CLOCK
    // =========================================================

    reg clk;


    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // =========================================================
    // DUT INPUTS
    // =========================================================

    reg rst_n;

    reg start;

    reg pixel_valid;

    reg [7:0] pixel_in;


    // =========================================================
    // DUT OUTPUTS
    // =========================================================

    wire result_valid;

    wire [5:0] class_out;

    wire [5:0] debug_status;

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

    reg [7:0] input_pixels [0:1023];


    // =========================================================
    // GOLDEN FILES
    // =========================================================

    reg [15:0] conv1_golden [0:14399];

    reg [15:0] pool1_golden [0:3599];

    reg [15:0] conv2_golden [0:5407];

    reg [15:0] pool2_golden [0:1151];

    reg [15:0] conv3_golden [0:1023];

    reg [15:0] dense1_golden [0:127];

    reg [15:0] output_golden [0:61];


    // =========================================================
    // VARIABLES
    // =========================================================

    integer i;

    integer mismatch_count;

    integer first_mismatch;

    integer checked_count;


    // =========================================================
    // TIMEOUT
    // =========================================================

    initial begin

        #30000000;

        $display("");
        $display("====================================================");
        $display(" TIMEOUT");
        $display("====================================================");

        $display(
            "FSM state = %0d",
            debug_status[3:0]
        );

        $finish;

    end


    // =========================================================
    // MAIN TEST
    // =========================================================

    initial begin

        // -----------------------------------------------------
        // Initial values
        // -----------------------------------------------------

        rst_n = 1'b0;

        start = 1'b0;

        pixel_valid = 1'b0;

        pixel_in = 8'd0;


        // -----------------------------------------------------
        // Header
        // -----------------------------------------------------

        $display("");
        $display("====================================================");
        $display(" CNN FULL OUTPUT VERIFICATION");
        $display("====================================================");
        $display("");


        // -----------------------------------------------------
        // Load files
        // -----------------------------------------------------

        $display(
            "Loading test_image_pixels.hex ..."
        );

        $readmemh(
            "test_image_pixels.hex",
            input_pixels
        );


        $display(
            "Loading conv1_golden.hex ..."
        );

        $readmemh(
            "conv1_golden.hex",
            conv1_golden
        );


        $display(
            "Loading pool1_golden.hex ..."
        );

        $readmemh(
            "pool1_golden.hex",
            pool1_golden
        );


        $display(
            "Loading conv2_golden.hex ..."
        );

        $readmemh(
            "conv2_golden.hex",
            conv2_golden
        );


        $display(
            "Loading pool2_golden.hex ..."
        );

        $readmemh(
            "pool2_golden.hex",
            pool2_golden
        );


        $display(
            "Loading conv3_golden.hex ..."
        );

        $readmemh(
            "conv3_golden.hex",
            conv3_golden
        );


        $display(
            "Loading dense1_golden.hex ..."
        );

        $readmemh(
            "dense1_golden.hex",
            dense1_golden
        );


        $display(
            "Loading output_golden.hex ..."
        );

        $readmemh(
            "output_golden.hex",
            output_golden
        );


        // -----------------------------------------------------
        // Reset
        // -----------------------------------------------------

        #100;

        rst_n = 1'b1;

        #100;


        // -----------------------------------------------------
        // Start CNN
        // -----------------------------------------------------

        $display("");
        $display("Starting CNN...");
        $display("");


        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;


        // -----------------------------------------------------
        // Send 1024 pixels
        // -----------------------------------------------------

        // -----------------------------------------------------
        // Send 1024 pixels - ONE rising edge per pixel, driven on negedge
        // -----------------------------------------------------

        for (
            i = 0;
            i < 1024;
            i = i + 1
        ) begin

            @(negedge clk);
            pixel_in    = input_pixels[i];
            pixel_valid = 1'b1;

            @(negedge clk);
            pixel_valid = 1'b0;

        end

        pixel_in = 8'd0;


        $display(
            "Input loading complete. Waiting for Output..."
        );


        // -----------------------------------------------------
        // Wait for Output state
        // -----------------------------------------------------

        wait (
            debug_status[3:0] == 4'd8
        );


        $display("");

        $display(
            "Output state reached at %0t ns.",
            $time
        );

        $display("");


        // -----------------------------------------------------
        // Wait for DEBUG
        // -----------------------------------------------------

        wait (
            debug_status[3:0] == 4'd10
        );


        #100;


        // =====================================================
        // FINAL DEBUG
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FINAL DEBUG STATE");
        $display("====================================================");

        $display(
            "FSM state      : %0d",
            debug_status[3:0]
        );

        $display(
            "Input checksum : %0d",
            input_checksum
        );

        $display(
            "Result valid   : %b",
            result_valid
        );

        $display(
            "Class out      : %0d",
            class_out
        );


        // =====================================================
        // CONV1
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FULL CONV1 RESULT");
        $display("====================================================");

        mismatch_count = 0;

        first_mismatch = -1;

        checked_count = 14400;


        for (
            i = 0;
            i < 14400;
            i = i + 1
        ) begin

            if (
                $signed(dut.act_bram_b[i]) !=
                $signed(conv1_golden[i])
            ) begin

                mismatch_count =
                    mismatch_count + 1;


                if (
                    first_mismatch == -1
                ) begin

                    first_mismatch =
                        i;

                end

            end

        end


        $display(
            "Checked     : %0d",
            checked_count
        );

        $display(
            "Mismatches  : %0d",
            mismatch_count
        );

        $display(
            "First mismatch : %0d",
            first_mismatch
        );


        // =====================================================
        // POOL1
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FULL POOL1 RESULT");
        $display("====================================================");

        mismatch_count = 0;

        first_mismatch = -1;

        checked_count = 3600;


        for (
            i = 0;
            i < 3600;
            i = i + 1
        ) begin

            if (
                $signed(dut.pool1_bram[i]) !=
                $signed(pool1_golden[i])
            ) begin

                mismatch_count =
                    mismatch_count + 1;


                if (
                    first_mismatch == -1
                ) begin

                    first_mismatch =
                        i;

                end

            end

        end


        $display(
            "Checked     : %0d",
            checked_count
        );

        $display(
            "Mismatches  : %0d",
            mismatch_count
        );

        $display(
            "First mismatch : %0d",
            first_mismatch
        );


        // =====================================================
        // CONV2
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FULL CONV2 RESULT");
        $display("====================================================");

        mismatch_count = 0;

        first_mismatch = -1;

        checked_count = 5408;


        for (
            i = 0;
            i < 5408;
            i = i + 1
        ) begin

            if (
                $signed(dut.act2_bram[i]) !=
                $signed(conv2_golden[i])
            ) begin

                mismatch_count =
                    mismatch_count + 1;


                if (
                    first_mismatch == -1
                ) begin

                    first_mismatch =
                        i;

                end

            end

        end


        $display(
            "Checked     : %0d",
            checked_count
        );

        $display(
            "Mismatches  : %0d",
            mismatch_count
        );

        $display(
            "First mismatch : %0d",
            first_mismatch
        );


        // =====================================================
        // POOL2
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FULL POOL2 RESULT");
        $display("====================================================");

        mismatch_count = 0;

        first_mismatch = -1;

        checked_count = 1152;


        for (
            i = 0;
            i < 1152;
            i = i + 1
        ) begin

            if (
                $signed(dut.pool2_bram[i]) !=
                $signed(pool2_golden[i])
            ) begin

                mismatch_count =
                    mismatch_count + 1;


                if (
                    first_mismatch == -1
                ) begin

                    first_mismatch =
                        i;

                end

            end

        end


        $display(
            "Checked     : %0d",
            checked_count
        );

        $display(
            "Mismatches  : %0d",
            mismatch_count
        );

        $display(
            "First mismatch : %0d",
            first_mismatch
        );


        // =====================================================
        // CONV3
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FULL CONV3 RESULT");
        $display("====================================================");

        mismatch_count = 0;

        first_mismatch = -1;

        checked_count = 1024;


        for (
            i = 0;
            i < 1024;
            i = i + 1
        ) begin

            if (
                $signed(dut.act_bram_a[i]) !=
                $signed(conv3_golden[i])
            ) begin

                mismatch_count =
                    mismatch_count + 1;


                if (
                    first_mismatch == -1
                ) begin

                    first_mismatch =
                        i;

                end

            end

        end


        $display(
            "Checked     : %0d",
            checked_count
        );

        $display(
            "Mismatches  : %0d",
            mismatch_count
        );

        $display(
            "First mismatch : %0d",
            first_mismatch
        );


        // =====================================================
        // DENSE1
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FULL DENSE1 RESULT");
        $display("====================================================");

        mismatch_count = 0;

        first_mismatch = -1;

        checked_count = 128;


        for (
            i = 0;
            i < 128;
            i = i + 1
        ) begin

            if (
                $signed(dut.dense1_bram[i]) !=
                $signed(dense1_golden[i])
            ) begin

                mismatch_count =
                    mismatch_count + 1;


                if (
                    first_mismatch == -1
                ) begin

                    first_mismatch =
                        i;

                end

            end

        end


        $display(
            "Checked     : %0d",
            checked_count
        );

        $display(
            "Mismatches  : %0d",
            mismatch_count
        );

        $display(
            "First mismatch : %0d",
            first_mismatch
        );


        // =====================================================
        // OUTPUT FIRST 20
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" OUTPUT FIRST 20 VALUES");
        $display("====================================================");


        for (
            i = 0;
            i < 20;
            i = i + 1
        ) begin

            $display(
                "%0d=%0d",
                i,
                $signed(dut.output_bram[i])
            );

        end


        // =====================================================
        // FULL OUTPUT
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FULL OUTPUT RESULT");
        $display("====================================================");

        mismatch_count = 0;

        first_mismatch = -1;

        checked_count = 62;


        for (
            i = 0;
            i < 62;
            i = i + 1
        ) begin

            if (
                $signed(dut.output_bram[i]) !=
                $signed(output_golden[i])
            ) begin

                mismatch_count =
                    mismatch_count + 1;


                if (
                    first_mismatch == -1
                ) begin

                    first_mismatch =
                        i;

                end


                if (
                    mismatch_count <= 20
                ) begin

                    $display(
                        "MISMATCH[%0d]: RTL=%0d (0x%04h) GOLDEN=%0d (0x%04h)",
                        i,
                        $signed(dut.output_bram[i]),
                        dut.output_bram[i],
                        $signed(output_golden[i]),
                        output_golden[i]
                    );

                end

            end

        end


        $display("");

        $display(
            "Checked     : %0d",
            checked_count
        );

        $display(
            "Mismatches  : %0d",
            mismatch_count
        );

        $display(
            "First mismatch : %0d",
            first_mismatch
        );


        // =====================================================
        // FINAL PIPELINE RESULT
        // =====================================================

        $display("");
        $display("====================================================");
        $display(" FINAL PIPELINE VERIFICATION");
        $display("====================================================");


        if (
            mismatch_count == 0
        ) begin

            $display("");

            $display(
                "* CONV1 + POOL1 + CONV2 + POOL2 + CONV3 + DENSE1 + OUTPUT PASS *"
            );

            $display("");

        end
        else begin

            $display("");

            $display(
                "* OUTPUT FAIL *"
            );

            $display(
                "First Output mismatch index = %0d",
                first_mismatch
            );

            $display("");

        end


        $display(
            "Final predicted class = %0d",
            class_out
        );


        $display("");
        $display("====================================================");
        $display(" SIMULATION FINISHED");
        $display("====================================================");
        $display("");


        #100;

        $finish;

    end


    // =========================================================
    // STATE MONITOR
    // =========================================================

    reg [3:0] previous_state;


    initial begin

        previous_state = 4'hF;

    end


    always @(posedge clk) begin

        if (
            debug_status[3:0] !==
            previous_state
        ) begin

            $display(
                "[%0t ns] STATE -> %0d   debug_status=0x%02h",
                $time,
                debug_status[3:0],
                debug_status
            );


            previous_state <=
                debug_status[3:0];

        end

    end


    // =========================================================
    // OUTPUT MAC TRACE
    //
    // First 12 MAC transactions.
    // =========================================================

    integer output_trace_count;


    initial begin

        output_trace_count = 0;

    end


    always @(posedge clk) begin

        if (
            debug_status[3:0] == 4'd8 &&
            output_trace_count < 12
        ) begin

            if (dut.out_busy) begin

                $display(
                    "[OUTPUT MAC %0d] time=%0t addr=%0d A=%0d (0x%04h) B=%0d (0x%04h)",
                    output_trace_count,
                    $time,
                    dut.out_mac_index,
                    $signed(dut.out_a_in),
                    dut.out_a_in,
                    $signed(dut.out_b_in),
                    dut.out_b_in
                );


                output_trace_count <=
                    output_trace_count + 1;

            end

        end

    end

endmodule