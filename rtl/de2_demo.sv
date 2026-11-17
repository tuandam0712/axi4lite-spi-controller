`timescale 1ns/1ps

module de2_demo #(
    parameter integer DEBOUNCE_CYCLES = 500000,
    parameter integer TIMEOUT_CYCLES  = 5000000
) (
    input  logic       CLOCK_50,
    input  logic [1:0] KEY,
    input  logic [9:0] SW,

    output logic [2:0] LEDR,
    output logic [6:0] HEX0, HEX1, HEX2, HEX3,

    output logic SPI_SCLK,
    output logic SPI_MOSI,
    output logic SPI_CS_N,
    input  logic SPI_MISO
);

    // Reset: asynchronous assertion, synchronized release.
    logic [1:0] reset_sync;
    logic rst_n;

    always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0])
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end

    assign rst_n = reset_sync[1];

    // Synchronize switches and debounce KEY1.
    logic [1:0] key_sync;
    logic [9:0] sw_meta, sw_sync;
    logic stable_key, previous_key;
    logic [31:0] debounce_count;
    logic trigger;

    always_ff @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            key_sync       <= 2'b11;
            sw_meta        <= '0;
            sw_sync        <= '0;
            stable_key     <= 1'b1;
            previous_key   <= 1'b1;
            debounce_count <= '0;
        end else begin
            key_sync     <= {key_sync[0], KEY[1]};
            sw_meta      <= SW;
            sw_sync      <= sw_meta;
            previous_key <= stable_key;

            if (key_sync[1] == stable_key) begin
                debounce_count <= '0;
            end else if (debounce_count == DEBOUNCE_CYCLES - 1) begin
                stable_key     <= key_sync[1];
                debounce_count <= '0;
            end else begin
                debounce_count <= debounce_count + 1'b1;
            end
        end
    end

    assign trigger = previous_key && !stable_key;

    typedef enum logic [2:0] {
        IDLE, WRITE, WRESP, READ, RRESP, DONE
    } state_t;

    state_t state;

    // Write sequence:
    // 0 CLKDIV, 1 LENGTH, 2 CTRL,
    // 3 TX byte0, 4 TX byte1, 5 START.
    logic [2:0] step;
    logic [1:0] mode;
    logic [7:0] tx0, tx1, rx0, rx1;
    logic rx_second;
    logic pass, fail;
    logic [31:0] watchdog;

    logic [7:0] awaddr, araddr;
    logic [31:0] wdata;
    logic awvalid, wvalid, arvalid;
    logic awready, wready, arready;
    logic bvalid, rvalid;
    logic [1:0] bresp, rresp;
    logic [31:0] rdata;
    logic core_busy;
    logic demo_busy;

    assign demo_busy = (state != IDLE && state != DONE);
    assign LEDR = {fail, pass, demo_busy};

    axi_spi_core core (
        .aclk          (CLOCK_50),
        .aresetn       (rst_n),

        .s_axi_awaddr  (awaddr),
        .s_axi_awprot  (3'b000),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),

        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (4'b0011),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),

        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (state == WRESP),

        .s_axi_araddr  (araddr),
        .s_axi_arprot  (3'b000),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),

        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (state == RRESP),

        .sclk          (SPI_SCLK),
        .mosi          (SPI_MOSI),
        .cs_n          (SPI_CS_N),
        .miso          (SPI_MOSI),
        .busy          (core_busy)
    );

    always_ff @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            step      <= '0;
            mode      <= '0;
            tx0       <= '0;
            tx1       <= '0;
            rx0       <= '0;
            rx1       <= '0;
            rx_second <= 1'b0;
            pass      <= 1'b0;
            fail      <= 1'b0;
            watchdog  <= '0;

            awaddr    <= '0;
            araddr    <= '0;
            wdata     <= '0;
            awvalid   <= 1'b0;
            wvalid    <= 1'b0;
            arvalid   <= 1'b0;
        end else begin
            if (demo_busy)
                watchdog <= watchdog + 1'b1;

            // Each VALID stays asserted until its own handshake.
            if (awvalid && awready)
                awvalid <= 1'b0;

            if (wvalid && wready)
                wvalid <= 1'b0;

            if (arvalid && arready)
                arvalid <= 1'b0;

            case (state)
                IDLE, DONE: begin
                    // A failure requires reset before retry.
                    if (trigger && !fail) begin
                        tx0       <= sw_sync[7:0];
                        tx1       <= ~sw_sync[7:0];
                        mode      <= sw_sync[9:8];
                        rx0       <= '0;
                        rx1       <= '0;
                        rx_second <= 1'b0;
                        pass      <= 1'b0;
                        fail      <= 1'b0;
                        watchdog  <= '0;
                        step      <= 3'd0;

                        // First write: CLKDIV = 25.
                        awaddr  <= 8'h08;
                        wdata   <= 32'd25;
                        awvalid <= 1'b1;
                        wvalid  <= 1'b1;
                        state   <= WRITE;
                    end
                end

                WRITE: begin
                    // AW and W may handshake on different clocks.
                    if ((!awvalid || awready) &&
                        (!wvalid  || wready))
                        state <= WRESP;
                end

                WRESP: begin
                    // BREADY is high in this state.
                    if (bvalid) begin
                        if (bresp != 2'b00) begin
                            pass  <= 1'b0;
                            fail  <= 1'b1;
                            state <= DONE;
                        end else if (step == 3'd5) begin
                            // START accepted. Poll STATUS.
                            araddr  <= 8'h04;
                            arvalid <= 1'b1;
                            state   <= READ;
                        end else begin
                            step    <= step + 1'b1;
                            awvalid <= 1'b1;
                            wvalid  <= 1'b1;
                            state   <= WRITE;

                            case (step)
                                3'd0: begin
                                    // Set LENGTH before enabling TX.
                                    awaddr <= 8'h14;
                                    wdata  <= 32'd2;
                                end

                                3'd1: begin
                                    // CTRL = {CPHA, CPOL, enable}.
                                    awaddr <= 8'h00;
                                    wdata  <= {29'b0, mode, 1'b1};
                                end

                                3'd2: begin
                                    awaddr <= 8'h0C;
                                    wdata  <= {24'b0, tx0};
                                end

                                3'd3: begin
                                    awaddr <= 8'h0C;
                                    wdata  <= {24'b0, tx1};
                                end

                                3'd4: begin
                                    awaddr <= 8'h18;
                                    wdata  <= 32'd1;
                                end

                                default: begin
                                    awaddr <= 8'h00;
                                    wdata  <= 32'd0;
                                end
                            endcase
                        end
                    end
                end

                READ: begin
                    if (arvalid && arready)
                        state <= RRESP;
                end

                RRESP: begin
                    // RREADY is high in this state.
                    if (rvalid) begin
                        if (rresp != 2'b00) begin
                            pass  <= 1'b0;
                            fail  <= 1'b1;
                            state <= DONE;
                        end else if (araddr == 8'h04) begin
                            // STATUS[6] = transaction DONE.
                            araddr  <= rdata[6] ? 8'h10 : 8'h04;
                            arvalid <= 1'b1;
                            state   <= READ;
                        end else if (!rx_second) begin
                            rx0       <= rdata[7:0];
                            rx_second <= 1'b1;

                            // Read second RX byte.
                            araddr  <= 8'h10;
                            arvalid <= 1'b1;
                            state   <= READ;
                        end else begin
                            rx1 <= rdata[7:0];

                            pass <= (rx0 == tx0) &&
                                    (rdata[7:0] == tx1);

                            fail <= (rx0 != tx0) ||
                                    (rdata[7:0] != tx1);

                            state <= DONE;
                        end
                    end
                end

                default: begin
                    pass  <= 1'b0;
                    fail  <= 1'b1;
                    state <= DONE;
                end
            endcase

            // Timeout locks the demo until reset.
            // It does not abort/reset the SPI core.
            if (demo_busy && watchdog >= TIMEOUT_CYCLES - 1) begin
                pass    <= 1'b0;
                fail    <= 1'b1;
                state   <= DONE;
                awvalid <= 1'b0;
                wvalid  <= 1'b0;
                arvalid <= 1'b0;
            end
        end
    end

    // Active-low segments: {g,f,e,d,c,b,a}.
    function automatic logic [6:0] hex_decode(
        input logic [3:0] nibble
    );
        case (nibble)
            4'h0: hex_decode = 7'b1000000;
            4'h1: hex_decode = 7'b1111001;
            4'h2: hex_decode = 7'b0100100;
            4'h3: hex_decode = 7'b0110000;
            4'h4: hex_decode = 7'b0011001;
            4'h5: hex_decode = 7'b0010010;
            4'h6: hex_decode = 7'b0000010;
            4'h7: hex_decode = 7'b1111000;
            4'h8: hex_decode = 7'b0000000;
            4'h9: hex_decode = 7'b0010000;
            4'hA: hex_decode = 7'b0001000;
            4'hB: hex_decode = 7'b0000011;
            4'hC: hex_decode = 7'b1000110;
            4'hD: hex_decode = 7'b0100001;
            4'hE: hex_decode = 7'b0000110;
            4'hF: hex_decode = 7'b0001110;
            default: hex_decode = 7'b1111111;
        endcase
    endfunction

    assign HEX3 = hex_decode(rx0[7:4]);
    assign HEX2 = hex_decode(rx0[3:0]);
    assign HEX1 = hex_decode(rx1[7:4]);
    assign HEX0 = hex_decode(rx1[3:0]);

endmodule