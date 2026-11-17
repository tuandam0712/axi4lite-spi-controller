`timescale 1ns/1ps
module axi_spi_core #(
    parameter int FIFO_DEPTH = 8
) (
    input logic aclk, aresetn,
    input logic [7:0] s_axi_awaddr,
    input logic [2:0] s_axi_awprot,
    input logic s_axi_awvalid, output logic s_axi_awready,
    input logic [31:0] s_axi_wdata,
    input logic [3:0] s_axi_wstrb,
    input logic s_axi_wvalid, output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid, input logic s_axi_bready,
    input logic [7:0] s_axi_araddr,
    input logic [2:0] s_axi_arprot,
    input logic s_axi_arvalid, output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid, input logic s_axi_rready,
    output logic sclk, mosi, cs_n, input logic miso,
    output logic busy
);
    localparam [7:0] CTRL=8'h00, STATUS=8'h04, CLKDIV=8'h08,
                     TXDATA=8'h0c, RXDATA=8'h10,
                     LENGTH=8'h14, COMMAND=8'h18, PROGRESS=8'h1c;
    // LENGTH=0 preserves legacy auto-send mode. LENGTH>0 requires COMMAND.START.
    logic [15:0] length_cfg, next_length, remaining, completed;
    logic txn_active, txn_done, engine_busy, keep_cs, start_txn;
    assign busy = txn_active || engine_busy;
    logic [2:0] ctrl;
    logic [15:0] divider;
    logic aw_pending, w_pending;
    logic [7:0] aw_addr;
    logic [31:0] w_data;
    logic [3:0] w_strb;
    logic commit;
    assign commit = aw_pending && w_pending && !s_axi_bvalid;
    logic read_access;
    assign read_access = s_axi_arvalid && s_axi_arready;
    logic [1:0] write_resp;
    logic [2:0] next_ctrl;
    logic [15:0] next_divider;
    logic tx_full, tx_empty, rx_full, rx_empty;
    logic [7:0] tx_head, rx_head, spi_rx;
    logic spi_done;
    logic launch;
    assign launch = aresetn && ctrl[0] && !engine_busy && !spi_done
                 && !tx_empty && !rx_full && !commit
                 && (txn_active || length_cfg==0);
    assign keep_cs = txn_active && remaining>1;
    assign start_txn = commit && write_resp==0 && aw_addr==COMMAND
                    && w_strb[0] && w_data[0];
    logic tx_push;
    assign tx_push = commit && write_resp==0 && aw_addr==TXDATA && w_strb[0];
    logic rx_pop;
    assign rx_pop = read_access && s_axi_araddr==RXDATA && !rx_empty;
    logic [$clog2(FIFO_DEPTH+1)-1:0] tx_count, rx_count;
    assign s_axi_awready = aresetn && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = aresetn && !w_pending && !s_axi_bvalid;
    assign s_axi_arready = aresetn && !s_axi_rvalid;
    always_comb begin
        write_resp=0; next_ctrl=ctrl; next_divider=divider; next_length=length_cfg;
        case (aw_addr)
            CTRL: if (w_strb!=0) begin
                if (busy) write_resp=2;
                else if (w_strb[0]) next_ctrl=w_data[2:0];
            end
            CLKDIV: if (w_strb!=0) begin
                if (w_strb[0]) next_divider[7:0]=w_data[7:0];
                if (w_strb[1]) next_divider[15:8]=w_data[15:8];
                if (busy || next_divider<5) begin
                    write_resp=2; next_divider=divider;
                end
            end
            TXDATA: if (w_strb[0] && tx_full) write_resp=2;
            LENGTH: if (w_strb!=0) begin
                if (busy || spi_done) write_resp=2;
                else begin
                    if (w_strb[0]) next_length[7:0]=w_data[7:0];
                    if (w_strb[1]) next_length[15:8]=w_data[15:8];
                end
            end
            COMMAND: if (w_strb[0] && w_data[0]) begin
                if (busy || spi_done || !ctrl[0] || length_cfg==0) write_resp=2;
            end
            STATUS, RXDATA, PROGRESS: if (w_strb!=0) write_resp=2;
            default: write_resp=2;
        endcase
    end
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            length_cfg<=0; remaining<=0; completed<=0; txn_active<=0; txn_done<=0;
            ctrl<=0; divider<=25; aw_pending<=0; w_pending<=0;
            aw_addr<=0; w_data<=0; w_strb<=0;
            s_axi_bvalid<=0; s_axi_bresp<=0;
            s_axi_rvalid<=0; s_axi_rresp<=0; s_axi_rdata<=0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending<=1; aw_addr<=s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending<=1; w_data<=s_axi_wdata; w_strb<=s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if (commit) begin
                aw_pending<=0; w_pending<=0;
                s_axi_bvalid<=1; s_axi_bresp<=write_resp;
                if (write_resp==0) begin ctrl<=next_ctrl; divider<=next_divider; length_cfg<=next_length; end
            end
            if (start_txn) begin
                txn_active<=1; txn_done<=0; remaining<=length_cfg; completed<=0;
            end
            if (txn_active && spi_done) begin
                remaining<=remaining-1'b1;
                completed<=completed+1'b1;
                if (remaining==1) begin txn_active<=0; txn_done<=1; end
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if (read_access) begin
                s_axi_rvalid<=1; s_axi_rresp<=0;
                case (s_axi_araddr)
                    CTRL: s_axi_rdata<={29'b0,ctrl};
                    STATUS: s_axi_rdata<={25'b0,txn_done,txn_active,rx_empty,rx_full,tx_empty,tx_full,busy};
                    CLKDIV: s_axi_rdata<={16'b0,divider};
                    LENGTH: s_axi_rdata<={16'b0,length_cfg};
                    COMMAND: s_axi_rdata<=0;
                    PROGRESS: s_axi_rdata<={16'b0,completed};
                    RXDATA: begin
                        s_axi_rdata<={24'b0,rx_head};
                        if (rx_empty) s_axi_rresp<=2;
                    end
                    default: begin s_axi_rdata<=0; s_axi_rresp<=2; end
                endcase
            end
        end
    end
    sync_fifo #(.DEPTH(FIFO_DEPTH)) tx_fifo (
        .clk(aclk),.rst_n(aresetn),.push(tx_push),.pop(launch),
        .din(w_data[7:0]),.dout(tx_head),.full(tx_full),.empty(tx_empty),.count(tx_count));
    sync_fifo #(.DEPTH(FIFO_DEPTH)) rx_fifo (
        .clk(aclk),.rst_n(aresetn),.push(spi_done),.pop(rx_pop),
        .din(spi_rx),.dout(rx_head),.full(rx_full),.empty(rx_empty),.count(rx_count));
    spi_master spi (
        .clk(aclk),.rst_n(aresetn),.start(launch),.tx_data(tx_head),
        .cpol(ctrl[1]),.cpha(ctrl[2]),.divider(divider),.miso(miso),
        .sclk(sclk),.mosi(mosi),.cs_n(cs_n),.busy(engine_busy),.keep_cs(keep_cs),.done(spi_done),.rx_data(spi_rx));
endmodule
