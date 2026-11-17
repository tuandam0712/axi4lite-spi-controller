`timescale 1ns/1ps
module sync_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 8,
    parameter int PW = (DEPTH <= 2) ? 1 : $clog2(DEPTH),
    parameter int CW = $clog2(DEPTH+1)
) (
    input logic clk, rst_n,
    input logic push, pop,
    input logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout,
    output logic full, empty,
    output logic [CW-1:0] count
);
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [PW-1:0] wr_ptr, rd_ptr;
    logic do_push, do_pop;
    assign do_push = push && !full;
    assign do_pop = pop && !empty;
    assign full = (count == DEPTH);
    assign empty = (count == 0);
    assign dout = empty ? {WIDTH{1'B0}} : mem[rd_ptr];
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            count <= 0; wr_ptr <=0; rd_ptr <=0 ;
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= din;
                wr_ptr <= (wr_ptr == DEPTH - 1) ? 0 : wr_ptr + 1'b1;
            end
            if (do_pop) begin
                rd_ptr <= (rd_ptr == DEPTH - 1) ? 0 : rd_ptr + 1'b1;
            end
            case ({do_push,do_pop})
                2'b10 : count <= count + 1'b1;
                2'b01: count <= count - 1'b1; 
                default: count <= count;
            endcase
        end
    end
endmodule