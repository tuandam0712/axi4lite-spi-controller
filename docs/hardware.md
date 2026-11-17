# DE2 demonstration and timing checklist

This project targets the **original DE2, Cyclone II EP2C35F672C6**. QSF is not for DE2-115 or another board.

## Controls

| Board signal | Meaning |
|---|---|
| KEY0 | Hold low to reset; release then wait before launch |
| KEY1 | Press to launch one switch-selected byte; debounced 10 ms |
| SW7..0 | TX byte; SW7 is MSB |
| SW8 | CPOL |
| SW9 | CPHA; numerical mode = 2*SW9 + SW8 |
| LEDR0 | Demo transaction in progress |
| LEDR1 | Last completed RX equals TX; PASS |
| LEDR2 | AXI error, timeout or RX mismatch; FAIL |
| HEX3/HEX2 | Captured TX, high/low nibble |
| HEX1/HEX0 | Received RX, high/low nibble |
| GPIO_0[0] | SCLK output, PIN_D25 |
| GPIO_0[1] | MOSI output, PIN_J22 |
| GPIO_0[2] | MISO input, PIN_E26 |
| GPIO_0[3] | CS_n output, PIN_E25 |

GPIO_0 array indices are the board's logical names; they are **not the numbered physical header positions**. Locate the matching header positions using the original DE2 manual/board diagram. Power off before placing a jumper. Connect MOSI GPIO_0[1] to MISO GPIO_0[2] only; do not connect SCLK or a power pin to MOSI.

## Test procedure

1. Compile and program `quartus/output_files/axi_spi_de2.sof` through USB-Blaster (JTAG). Program/Configure should reach 100%.
2. With loopback jumper installed, press/release KEY0. All result LEDs clear; HEX displays 00.
3. Set switches, wait for them to settle, press/release KEY1. Board divider is fixed D=25 (1 MHz). LEDR0 is brief and may not be visible; LEDR1 persists for a correct transfer. HEX RX must match TX; LEDR2 must remain off.
4. For every mode 0,1,2,3 test 00, FF, AA and 55 (16 tests). Change switches before pressing; current byte is latched on press.
5. Photograph board showing switches, HEX and PASS. Save Programmer success, Flow Summary, pins, setup/hold reports, and Questa waveform/transcript.

Expected example: mode0 and TX=A5 → HEX3..0 reads A5A5, LEDR1 on. With MISO deliberately tied to a defined logic 0 via a suitable external source, TX=FF receives00 → HEX FF00, LEDR2 on. A disconnected MISO is floating and is not a repeatable FAIL test. No pin changes while powered.

There is no real external SPI peripheral in the loopback test. Simulation uses an independent slave to check edge/bit behavior; board loopback validates the physical data path, controls and AXI integration.

## Timing/report remaining

SDC constrains CLOCK_50 to 20 ns; only first-stage async button/switch synchronization paths are excluded, plus asynchronous reset and human-facing outputs. SPI I/O budget of 5 ns is a conservative starting assumption relative to sys_clk. Verify input/output path timing and loopback propagation against that assumption. A real SPI peripheral requires constraints derived from its setup/hold and clock-to-output specifications; this SDC is not a universal peripheral constraint set.

In TimeQuest, verify synchronizer patterns match existing registers, no ignored constraints, and no unexpected unconstrained paths. Inspect setup and hold reports (both), recovery/removal where relevant, Fmax and worst paths. Fix violations before claiming closure. SCLK is not used as an internal clock. Do not add broad false paths to hide SPI or internal timing violations.

Record measured LEs/registers, memory bits, Fmax and setup/hold slack in the final report. None has been measured by the supplied Icarus simulation. Include photos only after a real board test; simulated wrapper PASS is separate evidence.
