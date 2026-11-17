# Recommended:
# cd D:/DoAn/TKIC/axi_spi
# do scripts/run_questa.do
# Fail immediately instead of continuing to add waves without a design.
onerror {abort}

set candidates [list [pwd] [file join [pwd] ..]]
set script_name [info script]
if {$script_name ne ""} {
    lappend candidates [file join [file dirname [file normalize $script_name]] ..]
}
set project_root ""
foreach candidate $candidates {
    set candidate [file normalize $candidate]
    if {[file exists [file join $candidate rtl axi_spi_core.sv]] &&
        [file exists [file join $candidate tb tb_axi_spi.sv]]} {
        set project_root $candidate
        break
    }
}
if {$project_root eq ""} {
    error "Project not found. First cd D:/DoAn/TKIC/axi_spi, then do scripts/run_questa.do"
}
cd $project_root

# Release the previous simulation before recompiling its library.
catch {quit -sim}
file mkdir reports
transcript file [file join $project_root reports questa_run.log]
transcript on
puts "PROJECT_ROOT: $project_root"

set sources [list rtl/sync_fifo.sv rtl/spi_master.sv rtl/axi_spi_core.sv \
    rtl/de2_demo.sv tb/tb_axi_spi.sv tb/tb_de2_demo.sv tb/tb_boundaries.sv]
foreach source_file $sources {
    if {![file exists $source_file]} {error "Missing source: $source_file"}
}
if {![file exists tb/vectors.hex]} {error "Missing tb/vectors.hex; run Python scripts/generate_vectors.py first"}

file mkdir build
set library_path [file join $project_root build work]
if {![file exists $library_path]} {vlib $library_path}
vmap axi_spi_work $library_path
puts "STEP: compile RTL and testbenches"
vlog -sv -work axi_spi_work {*}$sources

# Explicit search library for submodules during elaboration.
puts "STEP: load axi_spi_work.tb_axi_spi"
vsim -L axi_spi_work -voptargs=+acc axi_spi_work.tb_axi_spi
puts "DESIGN LOADED: tb_axi_spi"
onfinish stop

add wave -divider AXI
add wave sim:/tb_axi_spi/clk sim:/tb_axi_spi/resetn
add wave sim:/tb_axi_spi/awvalid sim:/tb_axi_spi/awready sim:/tb_axi_spi/awaddr
add wave sim:/tb_axi_spi/wvalid sim:/tb_axi_spi/wready sim:/tb_axi_spi/wdata
add wave sim:/tb_axi_spi/bvalid sim:/tb_axi_spi/bready sim:/tb_axi_spi/bresp
add wave sim:/tb_axi_spi/arvalid sim:/tb_axi_spi/arready sim:/tb_axi_spi/araddr
add wave sim:/tb_axi_spi/rvalid sim:/tb_axi_spi/rready sim:/tb_axi_spi/rdata
add wave -divider SPI
add wave sim:/tb_axi_spi/sclk sim:/tb_axi_spi/mosi sim:/tb_axi_spi/miso sim:/tb_axi_spi/cs_n
add wave sim:/tb_axi_spi/mode sim:/tb_axi_spi/expected_tx sim:/tb_axi_spi/slave_byte
add wave sim:/tb_axi_spi/dut/tx_count sim:/tb_axi_spi/dut/rx_count
run -all
wave zoom full
puts "Transcript saved: reports/questa_run.log"
