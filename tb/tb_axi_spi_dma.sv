`timescale 1ns/1ps
module tb_axi_spi_dma;
 logic clk=0;always #5 clk=~clk;
 logic rst=0;logic [7:0] awaddr=0,araddr=0;
 logic [31:0] wdata=0;logic [3:0] wstrb=3;
 logic awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
 wire awready,wready,bvalid,arready,rvalid;
 wire [1:0] bresp,rresp;wire [31:0] rdata;
 wire sclk,mosi,cs_n,busy;
 axi_spi_core #(.FIFO_DEPTH(2)) dut(
 .aclk(clk),.aresetn(rst),.s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),
 .s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),.s_axi_wstrb(wstrb),
 .s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
 .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
 .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
 .sclk(sclk),.mosi(mosi),.cs_n(cs_n),.miso(mosi),.busy(busy));
 task automatic wr(input logic[7:0] addr,input logic[31:0] data,input logic[1:0] expected_resp);
  @(negedge clk);awaddr=addr;awvalid=1;
  do @(posedge clk); while(!awready);
  @(negedge clk);awvalid=0;wdata=data;wvalid=1;
  do @(posedge clk); while(!wready);
  @(negedge clk);wvalid=0;bready=1;
  do @(posedge clk); while(!bvalid);
  if(bresp!==expected_resp) $fatal(1,"BRESP addr=%h got=%b",addr,bresp);
  @(negedge clk);bready=0;
 endtask
 task automatic rd(input logic[7:0] addr,output logic[31:0] data,input logic[1:0] expected_resp);
  logic[31:0] held;logic[1:0] held_resp;
  @(negedge clk);araddr=addr;arvalid=1;rready=0;
  do @(posedge clk);while(!arready);
  @(negedge clk);arvalid=0;
  while(!rvalid) @(negedge clk);
  held=rdata;held_resp=rresp;
  // Stall read response, including synchronous RAM responses.
  repeat(3) begin
   @(negedge clk);
   if(!rvalid || rdata!==held || rresp!==held_resp) $fatal(1,"R response unstable");
  end
  if(rresp!==expected_resp) $fatal(1,"RRESP addr=%h got=%b",addr,rresp);
  data=rdata;rready=1;@(posedge clk);@(negedge clk);rready=0;
 endtask
 function automatic logic[7:0] pattern(input integer i);pattern=8'((i*37)^8'hA5);endfunction
 logic[31:0] value;
 integer checks=0;
 task automatic run_case(input integer n,mode);
  wr(8'h00,32'(1 | (mode<<1)),0);
  wr(8'h08,5,0);
  wr(8'h14,32'(n),0);
  for(integer i=0;i<n;i++) begin wr(8'h20,32'(i),0);wr(8'h24,{24'b0,pattern(i)},0);end
  wr(8'h2c,1,0);
  wr(8'h0c,8'hEE,2); // CPU must not steal the DMA FIFO.
  rd(8'h10,value,2);
  wr(8'h24,8'hEE,2);
  value=0;
  for(integer t=0;t<100000 && !value[1];t++) rd(8'h30,value,0);
  if(!value[1] || busy || !cs_n) $fatal(1,"DMA did not finish");
  if(dut.dma_tx_count!=n || dut.dma_rx_count!=n) $fatal(1,"DMA counts incorrect");
  for(integer i=0;i<n;i++) begin
   wr(8'h20,32'(i),0);rd(8'h28,value,0);
   if(value!=={24'b0,pattern(i)}) $fatal(1,"RX RAM mismatch mode=%0d n=%0d i=%0d got=%h",mode,n,i,value);
   checks++;
  end
  $display("PASS AXI/RAM/DMA/SPI mode=%0d length=%0d",mode,n);
 endtask
 initial begin
  repeat(4) @(negedge clk);rst=1;
  wr(8'h2c,1,2); // Disabled and zero length.
  for(integer m=0;m<4;m++) begin run_case(2,m);run_case(256,m);end
  wr(8'h14,257,0);wr(8'h2c,1,2);
  $display("AXI DMA INTEGRATION PASSED: %0d RX bytes, R backpressure, register protection, restart",checks);
  $finish;
 end
 initial begin #10000000;$fatal(1,"Global timeout");end
endmodule
