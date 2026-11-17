`timescale 1ns/1ps
module tb_boundaries;
  reg test_passed=0;
  reg clk=0;always #10 clk=~clk;
  reg resetn=0,push=0,pop=0;
  reg [7:0] din=0;
  wire [7:0] dout;wire full,empty;wire [1:0] count;
  sync_fifo #(.DEPTH(3)) fifo(.clk(clk),.rst_n(resetn),.push(push),.pop(pop),
      .din(din),.dout(dout),.full(full),.empty(empty),.count(count));
  reg start=0;wire sclk,mosi,cs,busy,done;wire [7:0] rx;
  spi_master spi(.clk(clk),.rst_n(resetn),.start(start),.tx_data(8'ha5),
      .cpol(1'b1),.cpha(1'b1),.divider(16'hffff),.miso(mosi),
      .sclk(sclk),.mosi(mosi),.cs_n(cs),.busy(busy),.done(done),.rx_data(rx));
  integer cycles=0,last_edge=0,edges=0,i;
  always @(posedge clk) cycles=cycles+1;
  always @(sclk) if(!cs) begin
      if(edges!=0 && cycles-last_edge!=65535) $fatal(1,"Maximum divider spacing");
      last_edge=cycles;edges=edges+1;
  end
  task automatic fifo_op(input p,input q,input [7:0] d);
      begin @(negedge clk);push=p;pop=q;din=d;@(negedge clk);push=0;pop=0;end
  endtask
  initial begin
      repeat(4) @(negedge clk);resetn=1;repeat(2) @(negedge clk);
      fifo_op(0,1,0);if(!empty || count!=0) $fatal(1,"FIFO underflow");
      for(i=0;i<3;i=i+1) fifo_op(1,0,i+10);
      if(!full || count!=3) $fatal(1,"FIFO full");
      fifo_op(1,0,99);if(count!=3 || dout!=10) $fatal(1,"FIFO overflow");
      for(i=0;i<3;i=i+1) begin
          if(dout!=i+10) $fatal(1,"FIFO order");fifo_op(0,1,0);
      end
      for(i=0;i<20;i=i+1) begin
          fifo_op(1,0,i);fifo_op(1,1,i+1);
          if(count!=1 || dout!=i+1) $fatal(1,"Simultaneous FIFO operation / wrap");
          fifo_op(0,1,0);
      end
      @(negedge clk);start=1;@(negedge clk);start=0;
      wait(done);@(negedge clk);
      if(edges!=16 || rx!==8'ha5 || !cs || busy) $fatal(1,"Maximum divider byte");
      $display("PASS: depth-3 FIFO order/wrap/full/empty/simultaneous, divider 65535 full byte");test_passed=1;$finish;
  end
  initial begin #30000000;$fatal(1,"Boundary timeout");end
endmodule
