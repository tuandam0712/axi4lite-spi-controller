`timescale 1ns/1ps
module spi_master (
    input logic clk, rst_n, start,
    input logic [7:0] tx_data,
    input logic cpol, cpha,
    input logic [15:0] divider,
    input logic miso,
    input logic keep_cs,
    output logic sclk, mosi, cs_n, busy, done,
    output logic [7:0] rx_data
);
    typedef enum logic [2:0] {
        IDLE, LOAD, SHIFT, FINISH, WAIT_BYTE
    } state_t;
    state_t state;
    logic polarity, phase;
    logic [15:0] div_latched, ticks;
    logic [4:0] edges;
    logic [7:0] tx_shift, rx_shift;
    logic leading;
    assign leading = (sclk == polarity);
    logic hold_cs;
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            state <= IDLE; sclk <= 0; mosi <= 0; cs_n <= 1;
            busy <= 0; done <= 0; rx_data <= 0; tx_shift <= 0;
            rx_shift <= 0; ticks <= 0; edges <= 0;
            polarity <= 0; phase <= 0; div_latched <= 5;
            hold_cs <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE : begin
                    sclk <= cpol; cs_n <= 1;
                    if (start) begin
                        polarity <= cpol; phase <= cpha; div_latched <= divider;
                        tx_shift <= tx_data; rx_shift <= 0; ticks <= 0; edges <= 0;
                        mosi <= cpha ? 1'b0 : tx_data[7];
                        cs_n <= 0; busy <= 1; state <= LOAD;
                        hold_cs <= keep_cs;
                    end
                end
                LOAD : state <= SHIFT;
                SHIFT: begin
                    if (ticks == div_latched - 1'b1) begin
                        ticks <=0; sclk <= ~sclk;
                        if (leading != phase) begin
                            rx_shift <= {rx_shift[6:0], miso};
                        end else if (phase) begin
                            mosi <= tx_shift[7];
                            tx_shift <= {tx_shift[6:0], 1'b0};
                        end else begin
                            mosi <= tx_shift[6];
                            tx_shift <= {tx_shift[6:0], 1'b0};
                        end
                        if (edges == 15) state <= FINISH;
                        else edges <= edges + 1'b1;
                    end else ticks <= ticks + 1'b1;
                end
                FINISH : begin
                    rx_data <= rx_shift;
                    busy <= 1'b0;
                    done <= 1'b1;
                    sclk <= polarity;
                    if (hold_cs) begin
                        cs_n <= 1'b0;
                        state <= WAIT_BYTE;
                    end else begin
                        cs_n <= 1'b1;
                        state <= IDLE;
                    end
                end
                WAIT_BYTE : begin
                    cs_n <= 1'b0;
                    sclk <= polarity;
                    if (start) begin
                        tx_shift <= tx_data;
                        rx_shift <= 0;
                        ticks <= 0;
                        edges <= 0;
                        hold_cs <= keep_cs;
                        mosi <= phase ? 1'b0 : tx_data[7];
                        busy <= 1'b1;
                        state <= LOAD;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule