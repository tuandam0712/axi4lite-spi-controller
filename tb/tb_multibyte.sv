`timescale 1ns/1ps
module tb_multibyte;
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

  integer checks=0;
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

  integer mode=0, samples=0, edges_seen=0, frames=0, expected_n=0;
  logic monitor_enabled=0;
  logic [7:0] observed=0;
  logic [31:0] value;
  integer i,j,n,sent,received,m,frames_before;
  logic saved_sclk;

  function automatic [7:0] tx_pattern(input integer index);
    tx_pattern = 8'h96 + index * 37;
  endfunction
  function automatic [7:0] rx_pattern(input integer index);
    rx_pattern = 8'h27 + index * 53;
  endfunction

  // Independent SPI peripheral. Index is derived from wire sample edges,
  // not the DUT's byte_done, counters, state, or shift registers.
  always @(negedge cs_n) if (monitor_enabled) begin
    samples=0; edges_seen=0; observed=0;
    if (!mode[1]) miso = (rx_pattern(0) >> 7) & 1;
  end
  always @(sclk) if (monitor_enabled && !cs_n) begin
    edges_seen=edges_seen+1;
    if ((sclk != mode[0]) != mode[1]) begin
      observed={observed[6:0],mosi};
      if (samples%8==7 && observed !== tx_pattern(samples/8))
        $fatal(1,"TX wire mismatch mode=%0d byte=%0d got=%h expected=%h",
                   mode,samples/8,observed,tx_pattern(samples/8));
      samples=samples+1;
    end else if (samples < expected_n*8)
      miso = (rx_pattern(samples/8) >> (7-samples%8)) & 1;
  end
  always @(posedge cs_n) if (monitor_enabled && resetn) begin
    if (samples != expected_n*8 || edges_seen != expected_n*16)
      $fatal(1,"CS frame length samples=%0d edges=%0d bytes=%0d",
               samples,edges_seen,expected_n);
    frames=frames+1;
  end

  task automatic reset_core;
    begin
      monitor_enabled=0;
      @(negedge clk);resetn=0;awvalid=0;wvalid=0;arvalid=0;bready=0;rready=0;
      repeat(4) @(negedge clk);
      resetn=1;repeat(3) @(negedge clk);
      if (busy || !cs_n || bvalid || rvalid) $fatal(1,"Reset state");
    end
  endtask

  task automatic configure(input integer count,input integer spi_mode);
    begin
      reset_core();mode=spi_mode;expected_n=count;frames_before=frames;
      write_reg(8,5,3,1,0);
      write_reg(0,1|(spi_mode<<1),1,2,0);
      write_reg(20,count,3,0,0);
      monitor_enabled=1;
    end
  endtask

  task automatic check_complete(input integer count);
    begin
      read_reg(4,value,0);
      if (!value[6] || value[5] || value[0] || !cs_n)
        $fatal(1,"Transaction completion status %h",value);
      read_reg(28,value,0);
      if (value != count || frames != frames_before+1)
        $fatal(1,"Progress/frame count");
      repeat(30) @(negedge clk);
      if (!cs_n) $fatal(1,"Unexpected automatic restart");
      $display("PASS: multi-byte mode=%0d bytes=%0d",mode,count);
    end
  endtask

  initial begin
    // 20 full-duplex frames. Software supplies/drains FIFOs while active.
    for(m=0;m<4;m=m+1) begin
      for(j=0;j<5;j=j+1) begin
        case(j) 0:n=1;1:n=2;2:n=8;3:n=9;default:n=256;endcase
        configure(n,m);
        write_reg(12,tx_pattern(0),1,0,0);sent=1;received=0;
        repeat(20) @(negedge clk);
        if (!cs_n || busy) $fatal(1,"Must wait for explicit START");
        write_reg(24,1,1,1,0);
        // Configuration and repeated START are rejected throughout the frame.
        write_reg(0,0,1,0,2);
        write_reg(8,10,3,0,2);
        write_reg(20,7,3,0,2);
        write_reg(24,1,1,0,2);
        while(received<n) begin
          read_reg(4,value,0);
          if(sent<n && !value[1]) begin
            write_reg(12,tx_pattern(sent),1,sent%3,0);sent=sent+1;
          end
          read_reg(4,value,0);
          if(!value[4]) begin
            read_reg(16,value,0);
            if(value[7:0] !== rx_pattern(received))
              $fatal(1,"RX mismatch index=%0d got=%h expected=%h",received,value[7:0],rx_pattern(received));
            received=received+1;
          end
        end
        check_complete(n);
      end
    end

    // TX starvation: completed first byte, hold CS/SCLK until next byte exists.
    configure(2,0);
    write_reg(12,tx_pattern(0),1,0,0);write_reg(24,1,1,0,0);
    wait(dut.completed==1);repeat(3) @(negedge clk);saved_sclk=sclk;
    repeat(30) begin
      @(negedge clk);
      if(cs_n || !busy || sclk!==saved_sclk) $fatal(1,"TX starvation pause");
    end
    write_reg(12,tx_pattern(1),1,0,0);
    wait(dut.txn_done);repeat(2) @(negedge clk);
    for(i=0;i<2;i=i+1) begin
      read_reg(16,value,0);if(value[7:0]!==rx_pattern(i)) $fatal(1,"Starvation RX");
    end
    check_complete(2);

    // RX full: ninth byte must wait, even though TX data is available.
    configure(9,3);
    for(i=0;i<8;i=i+1) write_reg(12,tx_pattern(i),1,0,0);
    write_reg(24,1,1,0,0);wait(dut.rx_full);
    write_reg(12,tx_pattern(8),1,0,0);
    repeat(3) @(negedge clk);saved_sclk=sclk;
    repeat(30) begin
      @(negedge clk);
      if(cs_n || !busy || sclk!==saved_sclk || dut.completed!=8)
        $fatal(1,"RX full pause");
    end
    read_reg(16,value,0);if(value[7:0]!==rx_pattern(0)) $fatal(1,"Full RX first");
    wait(dut.txn_done);
    for(i=1;i<9;i=i+1) begin
      read_reg(16,value,0);if(value[7:0]!==rx_pattern(i)) $fatal(1,"Full RX resume");
    end
    check_complete(9);

    // A new START clears sticky DONE and resets progress, without resetting RTL.
    monitor_enabled=0;
    write_reg(20,1,3,0,0);expected_n=1;frames_before=frames;monitor_enabled=1;
    write_reg(24,1,1,0,0);
    read_reg(4,value,0);if(value[6] || !value[5]) $fatal(1,"START clears DONE");
    write_reg(12,tx_pattern(0),1,0,0);wait(dut.txn_done);
    read_reg(16,value,0);if(value[7:0]!==rx_pattern(0)) $fatal(1,"Restart RX");
    check_complete(1);

    // Reset aborts a live frame and clears both FIFOs.
    configure(9,2);write_reg(12,tx_pattern(0),1,0,0);write_reg(24,1,1,0,0);
    wait(!cs_n);repeat(20) @(negedge clk);reset_core();
    read_reg(4,value,0);if(value!==20) $fatal(1,"Reset clears frame/FIFOs");
    write_reg(24,1,1,0,2); // disabled and LENGTH=0
    write_reg(20,16'h0109,3,0,0);write_reg(20,0,2,0,0);
    read_reg(20,value,0);if(value!==9) $fatal(1,"LENGTH WSTRB merge");
    write_reg(20,7,0,0,0);read_reg(20,value,0);if(value!==9) $fatal(1,"LENGTH zero strobe");
    write_reg(28,1,1,0,2);read_reg(24,value,0);if(value!==0) $fatal(1,"COMMAND readback");
    test_passed=1;
    $display("PASS: multi-byte framing, distinct TX/RX, four modes, stalls, register errors, restart, reset");
    $finish;
  end
  initial begin #30000000;$fatal(1,"Multi-byte global timeout");end
endmodule
