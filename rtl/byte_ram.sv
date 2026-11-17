`timescale 1ns/1ps
module byte_ram #(parameter int ADDR_WIDTH=8)(
 input logic clk,wr_en,
 input logic [ADDR_WIDTH-1:0] wr_addr,
 input logic [7:0] wr_data,
 input logic rd_en,
 input logic [ADDR_WIDTH-1:0] rd_addr,
 output logic [7:0] rd_data
);
 localparam int DEPTH=1<<ADDR_WIDTH;
 logic [7:0] mem[0:DEPTH-1];
 always_ff @(posedge clk) begin
  if(wr_en) mem[wr_addr]<=wr_data;
  if(rd_en) rd_data<=mem[rd_addr];
 end
endmodule
