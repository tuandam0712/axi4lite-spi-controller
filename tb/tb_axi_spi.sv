`timescale 1ns/1ps
module tb_axi_spi;
  reg test_passed=0;
  reg clk=0; always #10 clk=~clk;
  reg resetn=0;
  reg [7:0] awaddr=0, araddr=0;
  reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
  reg [31:0] wdata=0;
  reg [3:0] wstrb=0;
  wire awready,wready,bvalid,arready,rvalid;
  wire [1:0] bresp,rresp;
  wire [31:0] rdata;
  wire sclk,mosi,cs_n,busy;
  reg miso=0;
  axi_spi_core dut(.aclk(clk),.aresetn(resetn),
    .s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
    .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
    .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
    .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
    .sclk(sclk),.mosi(mosi),.cs_n(cs_n),.miso(miso),.busy(busy));
  integer checks=0,bytes=0,mode=0,samples=0,edge_count=0;
  integer cycles=0,launch_cycle=0;
  always @(posedge clk) cycles=cycles+1;
  reg [7:0] slave_byte=0, expected_tx=0,observed_tx=0;
  reg monitor_enabled=0;
  // Independent SPI slave: drive on the opposite edge from sampling.
  always @(negedge cs_n) begin
    samples=0; edge_count=0; observed_tx=0;
    launch_cycle=cycles;
    if (!mode[1]) miso=slave_byte[7];
  end
  always @(sclk) if (!cs_n && monitor_enabled) begin
    edge_count=edge_count+1;
    if ((sclk != mode[0]) != mode[1]) begin
      observed_tx={observed_tx[6:0],mosi}; samples=samples+1;
    end else if(samples<8) miso=slave_byte[7-samples];
  end
  always @(posedge cs_n) if(resetn && monitor_enabled) begin
    if(cycles-launch_cycle!=82) $fatal(1,"D=5 byte completion latency");
    if(samples!=8 || edge_count!=16 || observed_tx!==expected_tx)
      $fatal(1,"SPI wire check: mode=%0d samples=%0d edges=%0d TX=%h expected=%h",
        mode,samples,edge_count,observed_tx,expected_tx);
    bytes=bytes+1;
  end
  always @(dut.rx_count) if(monitor_enabled && dut.rx_count==1)
    if(cycles-launch_cycle!=83) $fatal(1,"D=5 RX enqueue latency");
  task automatic write_reg(input [7:0] addr,input [31:0] data,input [3:0] strb,
                           input integer order,input [1:0] expected);
    reg [1:0] held;
    begin
      fork
        begin
          repeat(order==1 ? 3:0) @(negedge clk);
          @(negedge clk);awaddr=addr;awvalid=1;
          do @(posedge clk); while(!awready);
          @(negedge clk);awvalid=0;
        end
        begin
          repeat(order==2 ? 3:0) @(negedge clk);
          @(negedge clk);wdata=data;wstrb=strb;wvalid=1;
          do @(posedge clk); while(!wready);
          @(negedge clk);wvalid=0;
        end
      join
      wait(bvalid);held=bresp;
      repeat(3) begin @(negedge clk); if(!bvalid || bresp!==held) $fatal(1,"B stalled response changed");end
      if(bresp!==expected) $fatal(1,"WRITE %h response=%b expected=%b",addr,bresp,expected);
      bready=1;@(negedge clk);bready=0;checks=checks+1;
    end
  endtask
  task automatic read_reg(input [7:0] addr,output [31:0] data,input [1:0] expected);
    reg [31:0] held;
    begin
      @(negedge clk);araddr=addr;arvalid=1;
      do @(posedge clk); while(!arready);
      @(negedge clk);arvalid=0;wait(rvalid);held=rdata;
      repeat(3) begin @(negedge clk);if(!rvalid || rdata!==held || rresp!==expected) $fatal(1,"R response mismatch at %h",addr);end
      data=rdata;rready=1;@(negedge clk);rready=0;checks=checks+1;
    end
  endtask
  task automatic reset_core;
    begin
      monitor_enabled=0;
      @(negedge clk);resetn=0;
      awvalid=0;wvalid=0;arvalid=0;bready=0;rready=0;
      repeat(4) @(negedge clk);resetn=1;repeat(3) @(negedge clk);
      if(bvalid || rvalid || busy || !cs_n) $fatal(1,"Reset outputs");
    end
  endtask
  reg [31:0] value;
  reg [17:0] vectors [0:1015];
  integer i,j;
  initial begin
    $readmemh("tb/vectors.hex",vectors);
    reset_core();
    read_reg(0,value,0);if(value!==0) $fatal(1,"CTRL reset");
    read_reg(8,value,0);if(value!==25) $fatal(1,"DIV reset");
    read_reg(16,value,2);read_reg(1,value,2);read_reg(12,value,2);
    write_reg(8,4,15,1,2);write_reg(4,1,15,2,2);write_reg(3,1,0,0,2);
    write_reg(8,32'h105,3,1,0);write_reg(8,0,2,2,0);
    read_reg(8,value,0);if(value!==5) $fatal(1,"WSTRB merge");
    write_reg(0,7,0,0,0);read_reg(0,value,0);if(value!==0) $fatal(1,"zero strobes");
    fork
      write_reg(0,0,1,1,0);
      read_reg(8,value,0);
    join
    if(value!==5) $fatal(1,"Concurrent read/write");
    // FIFO full/empty and RX-full pause: disable monitoring for this batch.
    for(i=0;i<8;i=i+1) write_reg(12,i,1,i%3,0);
    write_reg(12,9,1,0,2);read_reg(4,value,0);if(!value[1]) $fatal(1,"TX full");
    write_reg(0,1,1,0,0);repeat(800) @(negedge clk);
    read_reg(4,value,0);if(!value[3] || !value[2]) $fatal(1,"RX full batch %h",value);
    write_reg(12,55,1,0,0);repeat(100) @(negedge clk);
    if(busy) $fatal(1,"RX full must pause SPI");
    read_reg(16,value,0);repeat(100) @(negedge clk);
    read_reg(4,value,0);if(!value[3]) $fatal(1,"Resume after pop");
    reset_core();write_reg(8,5,3,0,0);
    // Python reference vectors: 16 directed and 1000 seeded random bytes.
    for(i=0;i<1016;i=i+1) begin
      mode=vectors[i][17:16];
      write_reg(0,1|(mode<<1),1,i%3,0);
      expected_tx=vectors[i][15:8];slave_byte=vectors[i][7:0];monitor_enabled=1;
      write_reg(12,expected_tx,1,i%3,0);
      if(i==0) write_reg(8,9,3,0,2);
      wait(!cs_n);wait(cs_n);repeat(3) @(negedge clk);
      read_reg(16,value,0);
      if(value[7:0]!==slave_byte) $fatal(1,"RX mode=%0d got=%h expected=%h",mode,value,slave_byte);
    end
    // Abort a live byte and discard a partially received AXI write.
    monitor_enabled=0;write_reg(12,8'ha5,1,0,0);wait(busy);reset_core();
    @(negedge clk);awaddr=12;awvalid=1;@(negedge clk);awvalid=0;reset_core();
    read_reg(4,value,0);if(value!==20) $fatal(1,"Reset FIFO status");
    $display("PASS: %0d AXI checks; %0d SPI bytes; modes 0/1/2/3; FIFO, strobes, errors, reset, stalled B/R",checks,bytes);
    test_passed=1;$finish;
  end
  initial begin #10000000;$fatal(1,"Global timeout");end
endmodule
