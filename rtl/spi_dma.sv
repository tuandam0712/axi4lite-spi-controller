`timescale 1ns/1ps
module spi_dma #(parameter int ADDR_WIDTH=8)(
 input logic clk,rst_n,start,
 input logic [ADDR_WIDTH:0] length,
 output logic tx_rd_en,
 output logic [ADDR_WIDTH-1:0] tx_rd_addr,
 input logic [7:0] tx_rd_data,
 input logic tx_full,
 output logic tx_push,
 output logic [7:0] tx_data,
 input logic rx_empty,
 input logic [7:0] rx_data,
 output logic rx_pop,rx_wr_en,
 output logic [ADDR_WIDTH-1:0] rx_wr_addr,
 output logic [7:0] rx_wr_data,
 output logic busy,done,
 output logic [ADDR_WIDTH:0] tx_count,rx_count
);
 localparam int DEPTH=1<<ADDR_WIDTH;
 typedef enum logic [1:0] {TX_IDLE,TX_READ,TX_SEND} tx_state_t;
 tx_state_t tx_state;
 logic [ADDR_WIDTH:0] goal;
 logic rx_take;
 assign tx_rd_addr=tx_count[ADDR_WIDTH-1:0];
 assign tx_rd_en=rst_n && busy && tx_state==TX_READ;
 assign tx_push=rst_n && busy && tx_state==TX_SEND && !tx_full;
 assign tx_data=tx_rd_data;
 assign rx_take=rst_n && busy && rx_count<goal && !rx_empty;
 assign rx_pop=rx_take;
 assign rx_wr_en=rx_take;
 assign rx_wr_addr=rx_count[ADDR_WIDTH-1:0];
 assign rx_wr_data=rx_data;
 always_ff @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin tx_state<=TX_IDLE;goal<=0;tx_count<=0;rx_count<=0;busy<=0;done<=0;end
  else begin
   done<=0;
   if(!busy) begin
    if(start && length!=0 && length<=DEPTH) begin
     goal<=length;tx_count<=0;rx_count<=0;busy<=1;tx_state<=TX_READ;
    end
   end else begin
    case(tx_state)
     TX_READ: tx_state<=TX_SEND;
     TX_SEND: if(tx_push) begin
      tx_count<=tx_count+1'b1;
      if(tx_count==goal-1'b1) tx_state<=TX_IDLE;
      else tx_state<=TX_READ;
     end
     default:tx_state<=TX_IDLE;
    endcase
    if(rx_take) rx_count<=rx_count+1'b1;
    if(tx_count==goal && rx_count==goal) begin busy<=0;done<=1;tx_state<=TX_IDLE;end
   end
  end
 end
endmodule
