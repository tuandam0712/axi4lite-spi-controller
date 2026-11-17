`timescale 1ns/1ps

module tb_de2_demo;

    logic test_passed = 1'b0;

    logic clk = 1'b0;
    always #10 clk = ~clk;

    logic [1:0] key = 2'b11;
    logic [9:0] sw = '0;

    wire [2:0] led;
    wire [6:0] h0, h1, h2, h3;
    wire sclk, mosi, cs;

    logic break_loopback = 1'b0;
    wire miso = break_loopback ? 1'b0 : mosi;

    de2_demo #(
        .DEBOUNCE_CYCLES (4),
        .TIMEOUT_CYCLES  (4000)
    ) dut (
        .CLOCK_50 (clk),
        .KEY      (key),
        .SW       (sw),
        .LEDR     (led),
        .HEX0     (h0),
        .HEX1     (h1),
        .HEX2     (h2),
        .HEX3     (h3),
        .SPI_SCLK (sclk),
        .SPI_MOSI (mosi),
        .SPI_CS_N (cs),
        .SPI_MISO (miso)
    );

    integer frame_count = 0;
    integer frame_edges = 0;
    integer mode, i;
    logic frame_open = 1'b0;
    logic [7:0] pattern;

    // Track one continuous CS frame.
    always @(negedge cs) begin
        if (dut.rst_n) begin
            frame_count = frame_count + 1;
            frame_edges = 0;
            frame_open  = 1'b1;
        end
    end

    always @(sclk) begin
        if (frame_open && !cs && dut.rst_n)
            frame_edges = frame_edges + 1;
    end

    always @(posedge cs) begin
        frame_open = 1'b0;
    end

    task automatic reset_demo;
        begin
            @(negedge clk);
            key = 2'b10;

            repeat (5) @(negedge clk);
            key[0] = 1'b1;

            repeat (8) @(negedge clk);
        end
    endtask

    task automatic press_and_wait;
        integer frames_before;
        begin
            frames_before = frame_count;

            // Let switches pass through synchronizers.
            repeat (10) @(negedge clk);

            key[1] = 1'b0;
            repeat (12) @(negedge clk);
            key[1] = 1'b1;

            wait (led[0] === 1'b1);
            wait (led[0] === 1'b0);
            repeat (2) @(negedge clk);

            if (frame_count != frames_before + 1)
                $fatal(1,
                    "Expected one CS frame, got %0d",
                    frame_count - frames_before);

            // Two bytes: 16 full SCLK cycles = 32 edges.
            if (frame_edges != 32)
                $fatal(1,
                    "Expected 32 SCLK edges, got %0d",
                    frame_edges);

            if (cs !== 1'b1)
                $fatal(1, "CS must be released after transaction");
        end
    endtask

    initial begin
        reset_demo();

        // Repeated runs without reset, across all four modes.
        for (mode = 0; mode < 4; mode = mode + 1) begin
            for (i = 0; i < 4; i = i + 1) begin
                case (i)
                    0: pattern = 8'h00;
                    1: pattern = 8'hFF;
                    2: pattern = 8'hA5;
                    3: pattern = 8'h3C;
                endcase

                sw = {mode[1:0], pattern};
                break_loopback = 1'b0;

                press_and_wait();

                if (led !== 3'b010)
                    $fatal(1,
                        "Expected PASS: mode=%0d pattern=%h LED=%b",
                        mode, pattern, led);

                if (dut.rx0 !== pattern ||
                    dut.rx1 !== (~pattern))
                    $fatal(1,
                        "RX mismatch: mode=%0d TX=%h/%h RX=%h/%h",
                        mode, pattern, ~pattern,
                        dut.rx0, dut.rx1);

                if (dut.core.completed !== 16'd2)
                    $fatal(1, "Expected PROGRESS=2");

                if (dut.core.remaining !== 16'd0)
                    $fatal(1, "Expected remaining=0");

                if (dut.core.txn_active !== 1'b0 ||
                    dut.core.txn_done   !== 1'b1)
                    $fatal(1, "Wrong transaction status");

                $display(
                    "PASS mode=%0d TX=%h/%h RX=%h/%h edges=%0d",
                    mode, pattern, ~pattern,
                    dut.rx0, dut.rx1, frame_edges
                );
            end
        end

        // Force MISO low: FF/00 must not pass loopback check.
        break_loopback = 1'b1;
        sw = {2'b00, 8'hFF};

        press_and_wait();

        if (led !== 3'b100)
            $fatal(1, "Broken loopback must light FAIL");

        // Reset must clear status and release CS.
        @(negedge clk);
        key[0] = 1'b0;

        repeat (5) @(negedge clk);

        if (led !== 3'b000 || cs !== 1'b1)
            $fatal(1, "Reset must clear LEDs and release CS");

        $display(
            "PASS: 16 two-byte loopbacks, continuous CS, restart, mismatch and reset"
        );

        test_passed = 1'b1;
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "Global testbench timeout");
    end

endmodule