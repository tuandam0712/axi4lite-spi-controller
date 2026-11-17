`timescale 1ns/1ps
module tb_spi_dma;
 logic clk=0;always #5 clk=~clk;
 logic rst_n=0,start=0;
 logic [8:0] length=0;
 wire busy,done;wire [8:0] tx_count,rx_count;
 logic tx_wr_en=0,rx_rd_en=0;
 logic [7:0] tx_wr_addr=0,tx_wr_data=0,rx_rd_addr=0;
 wire tx_rd_en,rx_wr_en;
 wire [7:0] tx_rd_addr,tx_rd_data,rx_wr_addr,rx_wr_data,rx_rd_data;
 wire tx_push,tx_full,tx_empty,rx_pop,rx_full,rx_empty;
 wire [7:0] tx_data,tx_head,rx_head;
 byte_ram tx_ram(.clk(clk),.wr_en(tx_wr_en),.wr_addr(tx_wr_addr),.wr_data(tx_wr_data),
 .rd_en(tx_rd_en),.rd_addr(tx_rd_addr),.rd_data(tx_rd_data));
 byte_ram rx_ram(.clk(clk),.wr_en(rx_wr_en),.wr_addr(rx_wr_addr),.wr_data(rx_wr_data),
 .rd_en(rx_rd_en),.rd_addr(rx_rd_addr),.rd_data(rx_rd_data));
 spi_dma dma(.clk(clk),.rst_n(rst_n),.start(start),.length(length),
 .tx_rd_en(tx_rd_en),.tx_rd_addr(tx_rd_addr),.tx_rd_data(tx_rd_data),
 .tx_full(tx_full),.tx_push(tx_push),.tx_data(tx_data),
 .rx_empty(rx_empty),.rx_data(rx_head),.rx_pop(rx_pop),
 .rx_wr_en(rx_wr_en),.rx_wr_addr(rx_wr_addr),.rx_wr_data(rx_wr_data),
 .busy(busy),.done(done),.tx_count(tx_count),.rx_count(rx_count));
 logic pending=0;logic [7:0] held_byte=0;
 integer cycle=0,transferred=0,stall_cycles=0;
 wire tx_pop=rst_n && !tx_empty && !pending && cycle%7==0;
 wire rx_push=rst_n && pending && !rx_full && cycle%5==0;
 sync_fifo #(.DEPTH(2)) tx_fifo(.clk(clk),.rst_n(rst_n),.push(tx_push),.pop(tx_pop),
 .din(tx_data),.dout(tx_head),.full(tx_full),.empty(tx_empty),.count());
 sync_fifo #(.DEPTH(2)) rx_fifo(.clk(clk),.rst_n(rst_n),.push(rx_push),.pop(rx_pop),
 .din(held_byte),.dout(rx_head),.full(rx_full),.empty(rx_empty),.count());
 function automatic logic [7:0] pattern(input integer index);
  pattern=8'((index*37)^8'hA5);
 endfunction
 always @(posedge clk) begin
  if(!rst_n) begin cycle<=0;pending<=0;transferred<=0;held_byte<=0;stall_cycles<=0;end
  else begin
   cycle<=cycle+1;
   if(busy && tx_full) stall_cycles<=stall_cycles+1;
   if(tx_pop) begin
    if(tx_head!==pattern(transferred)) $fatal(1,"TX mismatch at %0d",transferred);
    held_byte<=tx_head;pending<=1;transferred<=transferred+1;
   end
   if(rx_push) pending<=0;
  end
 end
 task automatic run_case(input integer n);
  @(negedge clk);rst_n=0;start=0;tx_wr_en=0;rx_rd_en=0;
  repeat(3) @(negedge clk);rst_n=1;
  for(integer i=0;i<n;i++) begin
   @(negedge clk);tx_wr_en=1;tx_wr_addr=8'(i);tx_wr_data=pattern(i);
  end
  @(negedge clk);tx_wr_en=0;length=9'(n);start=1;
  @(negedge clk);start=0;
  wait(done===1);@(negedge clk);
  if(busy || tx_count!=n || rx_count!=n || transferred!=n) $fatal(1,"Completion count mismatch");
  for(integer i=0;i<n;i++) begin
   rx_rd_en=1;rx_rd_addr=8'(i);@(negedge clk);
   if(rx_rd_data!==pattern(i)) $fatal(1,"RX mismatch at %0d",i);
  end
  rx_rd_en=0;
  if(n==256 && stall_cycles==0) $fatal(1,"No backpressure exercised");
  if(done!==0) $fatal(1,"DONE not a pulse");
  $display("PASS length=%0d stalls=%0d",n,stall_cycles);
 endtask
 initial begin
  run_case(1);run_case(2);run_case(9);run_case(256);
  $display("DMA/RAM TEST PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
