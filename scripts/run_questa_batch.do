onerror {quit -code 1 -force}
set project_root [file normalize [file join [file dirname [info script]] ..]]
cd $project_root
file mkdir build
if {![file exists build/work]} {vlib build/work}
vmap axi_spi_work build/work
vlog -sv -work axi_spi_work rtl/sync_fifo.sv rtl/spi_master.sv rtl/axi_spi_core.sv rtl/de2_demo.sv tb/tb_axi_spi.sv tb/tb_de2_demo.sv tb/tb_boundaries.sv
foreach top {tb_axi_spi tb_de2_demo tb_boundaries} {
    vsim axi_spi_work.$top
    onfinish stop
    run -all
    if {[examine -radix decimal sim:/$top/test_passed] != 1} {quit -code 1 -force}
    # Normal completion reaches $finish; fatal assertions trigger onerror.
    quit -sim
}
quit -code 0 -force
