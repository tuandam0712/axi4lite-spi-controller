# Baseline system-clock constraints. SPI is an output, NOT an internal clock.
create_clock -name sys_clk -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty
# KEY0 asynchronously asserts reset; release is synchronized inside the wrapper.
set_false_path -from [get_ports {KEY[0]}]
# Only asynchronous inputs to the FIRST synchronizer stage are excluded.
set_false_path -from [get_ports {KEY[1]}] -to [get_registers {*key_sync[0]}]
set_false_path -from [get_ports {SW[*]}] -to [get_registers {*sw_meta[*]}]
# Conservative loopback timing budget: MISO stable within 5 ns of sys_clk.
# These are assumptions to verify physically, not measured board delays.
set_input_delay -clock sys_clk -max 5.000 [get_ports {SPI_MISO}]
set_input_delay -clock sys_clk -min 0.000 [get_ports {SPI_MISO}]
set_output_delay -clock sys_clk -max 5.000 [get_ports {SPI_SCLK SPI_MOSI SPI_CS_N}]
set_output_delay -clock sys_clk -min 0.000 [get_ports {SPI_SCLK SPI_MOSI SPI_CS_N}]
# Human-readable LEDs/HEX have no synchronous external receiver.
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*]}]
