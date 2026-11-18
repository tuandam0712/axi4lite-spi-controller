# AXI4-Lite to SPI Master Controller

Authors: Dam Phuc Tuan

This project implements a register-controlled SPI master in SystemVerilog. The current `axi_spi_core` supports CPU-driven FIFO transfers, explicit multi-byte transactions with continuous chip select, and a local RAM-to-FIFO DMA engine. This README documents the current register decode in `rtl/axi_spi_core.sv`.

## Interfaces and capabilities

- AXI4-Lite slave: 32-bit data, 8-bit byte address, four write strobes, and independent AW/W buffering. One read and one write may be outstanding; reads and writes may overlap. AWPROT and ARPROT are ignored.
- SPI: one active-low `cs_n`, 8-bit words, MSB first, full duplex, and all four CPOL/CPHA modes.
- Separate TX/RX FIFOs with `FIFO_DEPTH` entries each (default: 8 bytes). Use a depth of at least 2; non-power-of-two depths are supported.
- CPU-driven transfers: automatic single-byte framing or explicit transactions of 1 to 65535 bytes.
- DMA transfers: 1 to 256 bytes between separate internal 256-byte TX/RX RAMs and the SPI FIFOs. The engine does not access external system memory and is not an AXI bus master.
- One clock domain, `aclk`. SCLK is a registered output. `aresetn` is asynchronous and active low; the integrator must synchronize its release.

There are no interrupts, programmable transfer timeouts, software abort commands, or FIFO flush registers. Reset is required to abort a stalled transaction.

## Register map

All addresses are **byte offsets** from the peripheral base address. For example, CLKDIV is at `BASE + 0x08`. The integration supplies BASE; the core receives only the 8-bit offset. Decode uses the complete address without rounding or aliasing. Unlisted addresses, including misaligned addresses, return SLVERR.

RW means readable/writable, RO means read-only, and WO means write-only. Reserved read bits return zero; reserved write data bits are ignored on permitted writes. AXI responses are `OKAY = 2'b00` and `SLVERR = 2'b10`.

| Offset | Register | Access | Defined bits | Reset/read state | Purpose |
|---|---|---|---|---|---|
| `0x00` | CTRL | RW | `[2:0]` | `0x00000000` | Enable, CPOL, CPHA |
| `0x04` | STATUS | RO | `[6:0]` | `0x00000014` | Busy, FIFO flags, transaction status |
| `0x08` | CLKDIV | RW | `[15:0]` | `0x00000019` (25) | SCLK half-period in aclk cycles |
| `0x0C` | TXDATA | WO | `[7:0]` | No readback | Push one TX FIFO byte |
| `0x10` | RXDATA | RO/pop | `[7:0]` | Empty read returns SLVERR | Read and remove one RX FIFO byte |
| `0x14` | LENGTH | RW | `[15:0]` | `0x00000000` | Automatic mode or transaction byte count |
| `0x18` | COMMAND | Start strobe/read-zero | `[0]` | Reads `0x00000000` | Start a CPU-driven transaction |
| `0x1C` | PROGRESS | RO | `[15:0]` | `0x00000000` | Completed SPI bytes in an explicit transaction |
| `0x20` | MEM_ADDR | RW | `[7:0]` | `0x00000000` | Shared CPU index into TX/RX RAM |
| `0x24` | TX_MEM | WO | `[7:0]` | No readback; RAM uninitialized | Write TX RAM at MEM_ADDR |
| `0x28` | RX_MEM | RO | `[7:0]` | RAM uninitialized | Read RX RAM at MEM_ADDR |
| `0x2C` | DMA_COMMAND | Start strobe/read-zero | `[0]` | Reads `0x00000000` | Start a RAM-backed transaction |
| `0x30` | DMA_STATUS | RO | `[1:0]` | `0x00000000` | DMA busy and sticky completion |

### 0x00 — CTRL

| Bits | Field | Meaning |
|---|---|---|
| `0` | ENABLE | Allow byte launches when 1; reset: 0. |
| `1` | CPOL | SCLK idle polarity; reset: 0. |
| `2` | CPHA | SPI clock phase; reset: 0. |
| `31:3` | Reserved | Read as zero. |

Only WSTRB[0] updates these fields. Any nonzero-strobe write while STATUS.BUSY=1 returns SLVERR, including writes that select only reserved byte lanes. Disabling SPI does not flush either FIFO.

| SPI mode | CPOL | CPHA | Sample edge | Change-data edge | CTRL with ENABLE=1 |
|---|---|---|---|---|---|
| 0 | 0 | 0 | Rising | Falling | `0x01` |
| 1 | 0 | 1 | Falling | Rising | `0x05` |
| 2 | 1 | 0 | Falling | Rising | `0x03` |
| 3 | 1 | 1 | Rising | Falling | `0x07` |

### 0x04 — STATUS

| Bit | Field | Meaning when 1 |
|---|---|---|
| `0` | BUSY | Explicit transaction active, SPI engine busy, or DMA busy. Also drives the top-level busy output. |
| `1` | TX_FULL | TX FIFO cannot accept another CPU byte. |
| `2` | TX_EMPTY | TX FIFO contains no queued bytes. |
| `3` | RX_FULL | RX FIFO is full; another SPI byte will not launch. |
| `4` | RX_EMPTY | RX FIFO contains no readable bytes. |
| `5` | TXN_ACTIVE | An explicit CPU-driven or DMA transaction is active. |
| `6` | TXN_DONE | Sticky completion of the last explicit SPI transaction. |
| `31:7` | Reserved | Read as zero. |

TXN_DONE clears on reset or an accepted COMMAND.START/DMA_COMMAND.START. Reading STATUS or changing LENGTH does not clear it. STATUS writes with nonzero strobes return SLVERR; writing a 1 does not clear any flag.

BUSY does not indicate whether the FIFOs contain pending data. In automatic mode it can be low between bytes, including a brief completion-to-RX-enqueue interval. Poll RX_EMPTY before reading RXDATA. For DMA, TXN_DONE indicates SPI completion; use DMA_STATUS.DONE to confirm that received data has reached RX RAM.

### 0x08 — CLKDIV

Bits [15:0] hold divider D, the number of aclk cycles per SCLK half-period. WSTRB[0] updates bits [7:0]; WSTRB[1] updates bits [15:8]. The merged value must be in `5..65535`. A nonzero-strobe write returns SLVERR if BUSY is set or the merged value is below 5; the previous divider is retained.

During clocking, `f_SCLK = f_aclk / (2 * D)`. For a 50 MHz input clock, the reset divider 25 gives 1 MHz SCLK, and divider 5 gives 5 MHz. These are clock-divider calculations, not measured hardware limits. Byte boundaries and FIFO stalls reduce transfer throughput.

### 0x0C — TXDATA and 0x10 — RXDATA

- A TXDATA write with WSTRB[0]=1 enqueues WDATA[7:0]. A full FIFO returns SLVERR. Without WSTRB[0], the write is an accepted no-op unless DMA is busy. Reading TXDATA always returns SLVERR.
- A successful RXDATA read returns the oldest byte in [7:0], with [31:8]=0, and pops it once at the AR handshake. Stalling the R response does not repeat the pop. An empty read returns zero with SLVERR.
- While DMA is busy, all TXDATA writes and RXDATA reads return SLVERR; DMA owns the FIFO interfaces.
- RXDATA writes with nonzero strobes return SLVERR.

FIFO admission uses the state before the clock edge. A full-TX write can fail even if a byte is popped on that edge; an empty-RX read can fail even if a byte is pushed on that edge. Check responses and retry as needed.

### 0x14 — LENGTH

Bits [15:0] select the transfer behavior:

- `0`: automatic mode. When enabled, queued bytes launch whenever the engine is available and RX has room. CS is released after each byte. No START write is needed.
- `1..65535`: explicit transaction mode. Queued bytes wait for an accepted START. A CPU-driven transaction sends exactly LENGTH bytes, holding CS low across byte boundaries.
- DMA accepts only `1..256`; the wider range is available only to CPU-driven transfers.

WSTRB[0] and WSTRB[1] update the low and high bytes. A nonzero-strobe write returns SLVERR while BUSY or the internal one-cycle SPI completion pulse is asserted. LENGTH is retained after completion; it is not a remaining-byte counter.

### 0x18 — COMMAND and 0x1C — PROGRESS

Writing COMMAND[0]=1 with WSTRB[0]=1 requests START. It returns SLVERR if BUSY is set, the SPI completion pulse is asserted, ENABLE is 0, or LENGTH is 0. Other COMMAND writes are accepted no-ops; reads return zero.

An accepted START sets TXN_ACTIVE, clears TXN_DONE, clears PROGRESS, and loads the remaining count from LENGTH. START does not clear the FIFOs or require an initial TX byte. Each completed SPI byte increments PROGRESS[15:0]. Completion of the last byte clears TXN_ACTIVE and sets TXN_DONE. Automatic-mode bytes do not update PROGRESS. PROGRESS retains its value until reset or another accepted START, including DMA START. Nonzero-strobe writes to PROGRESS return SLVERR.

During an explicit transaction, TX starvation or RX-full backpressure pauses the transfer with CS low and SCLK at its idle polarity. Software must feed TX and drain RX to resume. There are inter-byte gaps even without starvation; continuous CS does not imply uninterrupted SCLK. Queued bytes beyond LENGTH remain in TX FIFO.

### 0x20 — MEM_ADDR, 0x24 — TX_MEM, and 0x28 — RX_MEM

MEM_ADDR selects byte index `0..255` for CPU RAM accesses. WSTRB[0] writes its low byte; upper write data bits are ignored. It does **not auto-increment**. Reads return the current index even while BUSY.

TX_MEM writes WDATA[7:0] to TX RAM at MEM_ADDR when WSTRB[0]=1. Other strobes do not write RAM. TX_MEM cannot be read. RX_MEM reads return RX RAM at MEM_ADDR in [7:0], with the upper bits zero. RX_MEM reads are non-destructive and use synchronous RAM, so their AXI response arrives one aclk cycle later than ordinary register reads.

While BUSY, all MEM_ADDR/TX_MEM writes return SLVERR, even with zero strobes, and RX_MEM reads return zero with SLVERR. RX_MEM writes with nonzero strobes return SLVERR.

The TX/RX RAM arrays have no reset initialization. Reset does not clear their contents. Initialize every TX byte that DMA will read, and only interpret RX bytes written by a completed transfer. MEM_ADDR affects CPU access only: each DMA transfer starts at RAM index 0 regardless of MEM_ADDR.

### 0x2C — DMA_COMMAND and 0x30 — DMA_STATUS

Writing DMA_COMMAND[0]=1 with WSTRB[0]=1 requests DMA START. The request is accepted only when all these conditions hold:

- BUSY is 0 and the SPI completion pulse is not asserted.
- ENABLE is 1 and LENGTH is in `1..256`.
- Both TX and RX FIFOs are empty.
- No RX_MEM read is pending or being accepted on the same edge.

Otherwise START returns SLVERR. Other DMA_COMMAND writes are accepted no-ops; reads return zero. An accepted DMA START also starts the explicit SPI transaction and resets its PROGRESS/TXN_DONE state.

| DMA_STATUS bit | Field | Meaning |
|---|---|---|
| `0` | BUSY | DMA is moving or waiting to move bytes. |
| `1` | DONE | Sticky indication that all requested TX bytes were queued and all RX bytes were stored in RAM. |
| `31:2` | Reserved | Read as zero. |

DMA DONE clears on reset or the next accepted **DMA** START. A CPU-driven START does not clear it. Reads do not clear it; nonzero-strobe writes to DMA_STATUS return SLVERR. DONE can become visible after SPI TXN_DONE, so poll DMA DONE before reading received RAM data.

### Write strobes and error handling

Successful accesses return OKAY. Rejected accesses do not perform the requested register write, FIFO push/pop, or RAM operation; ongoing transfers may still advance independently.

- Zero-strobe writes to mapped registers are generally OKAY no-ops. Exceptions: TXDATA rejects them while DMA is busy; MEM_ADDR and TX_MEM reject them while BUSY. Unmapped writes always return SLVERR.
- Writes to STATUS, RXDATA, PROGRESS, RX_MEM, and DMA_STATUS return SLVERR when any strobe is set.
- CTRL, CLKDIV, and LENGTH apply busy checks to **any nonzero strobe**, even when only reserved byte lanes are selected.
- START is a write action, not a stored bit or a write-one-to-clear flag. Only data bit 0 together with WSTRB bit 0 requests it.
- Unsupported reads, including TXDATA and TX_MEM, return zero with SLVERR.

AXI responses remain valid until accepted by the master. Software should check BRESP/RRESP rather than assuming an access succeeded.

## Programming sequences

### Automatic single-byte transfers

1. Wait for BUSY=0, disable SPI, and configure CLKDIV and LENGTH=0.
2. Write CTRL with the required CPOL/CPHA and ENABLE=1.
3. When TX_FULL=0, write the next byte to TXDATA with WSTRB[0]=1.
4. When RX_EMPTY=0, read RXDATA and check RRESP. Repeat for each byte.

Each transmitted byte produces a received byte, even for a protocol that only uses MOSI. Keep draining RX to prevent it from blocking further launches.

### CPU-driven multi-byte transaction

1. Wait for BUSY=0. Establish known FIFO contents; reset first if stale TX data cannot otherwise be accounted for, and drain any old RX data.
2. With launch disabled, configure CLKDIV, a nonzero LENGTH, and then CTRL with the desired mode and ENABLE=1.
3. Optionally preload up to FIFO_DEPTH TX bytes, then write `0x01` to COMMAND.
4. While active, poll STATUS, enqueue remaining TX bytes when space is available, and drain RX when data is available. For long transfers, service both directions rather than filling all TX first.
5. Collect exactly LENGTH received bytes and poll TXN_DONE. PROGRESS reports completed SPI bytes.

### RAM-backed DMA transaction

1. Wait for BUSY=0 and establish empty TX/RX FIFOs. Reset clears both FIFOs if needed.
2. Configure CLKDIV, LENGTH in `1..256`, and CTRL with the desired mode and ENABLE=1. Set a nonzero LENGTH before enabling launch of any queued data.
3. For each i from 0 to LENGTH-1, write i to MEM_ADDR and the outgoing byte to TX_MEM. Use WSTRB[0]=1 for both writes.
4. Write `0x01` to DMA_COMMAND and check BRESP. Do not access the CPU FIFO data ports while DMA is busy.
5. Poll DMA_STATUS until DONE=1 and BUSY=0.
6. For each i, write i to MEM_ADDR and read RX_MEM. No address auto-increment occurs.

## Reset behavior and integration limits

Reset aborts SPI and DMA, deasserts CS, clears FIFO pointers/counts, resets configuration and sticky status, and discards pending AXI transactions/responses. SCLK resets to 0; when idle after reset it follows CPOL. RAM contents are not reset. The AXI master must discard interrupted requests and restart after reset.

The SPI engine latches mode and divider at byte launch. Explicit transactions prohibit configuration changes while active. In automatic mode, BUSY may be low with queued data present; disable launch and configure before enabling it when a precise configuration boundary is required.

START cannot abort or restart an active transaction. Insufficient TX data or an undrained full RX FIFO can leave an explicit transaction active indefinitely, holding CS low. The connected SPI peripheral must tolerate clock pauses.

## Simulation with Questa

Run the following in the Questa Transcript from the project root. The compile list includes the RAM and DMA modules required by the current core.

```tcl
vlib build_readme_work
vmap axi_spi_readme_work build_readme_work
vlog -sv -work axi_spi_readme_work rtl/sync_fifo.sv rtl/byte_ram.sv rtl/spi_dma.sv rtl/spi_master.sv rtl/axi_spi_core.sv tb/tb_axi_spi.sv tb/tb_boundaries.sv tb/tb_multibyte.sv tb/tb_spi_dma.sv tb/tb_axi_spi_dma.sv

vsim -voptargs=+acc axi_spi_readme_work.tb_multibyte
onfinish stop
add wave -r sim:/tb_multibyte/*
run -all
```

To run another test after compilation:

```tcl
quit -sim
vsim -voptargs=+acc axi_spi_readme_work.tb_axi_spi_dma
onfinish stop
run -all
```

The same pattern applies to the other tops below. `tb_axi_spi` reads the checked-in `tb/vectors.hex`; regenerate it if needed with `python scripts/generate_vectors.py`, using Python 3 from the project root. Inspect assertion failures and each test's final success message; reaching the end of an arbitrary simulation interval alone is not a pass.

| Testbench | Checks present in the source |
|---|---|
| `tb_axi_spi` | Independent SPI slave, directed/random byte vectors, four modes, AXI ordering/backpressure, access errors, FIFO stalls, reset, and byte timing |
| `tb_boundaries` | Depth-3 FIFO wrap/full/empty behavior and maximum-divider SPI transfer |
| `tb_multibyte` | Four modes; lengths 1, 2, 8, 9, and 256; distinct TX/RX patterns; CS framing; TX starvation; RX-full pause/resume; restart and reset |
| `tb_spi_dma` | Standalone DMA/RAM/FIFO transfers of 1, 2, 9, and 256 bytes, including backpressure |
| `tb_axi_spi_dma` | AXI/RAM/DMA/SPI integration with depth-2 FIFOs, four modes, lengths 2 and 256, MOSI-to-MISO loopback, RAM read backpressure, and access protection |

These describe implemented test scenarios, not a claim that the current revision has passed them. Questa was not run for this README update. Existing logs are historical evidence for their recorded runs, not certification of every current feature. No formal proof, exhaustive AXI compliance result, measured coverage percentage, synthesis utilization, timing closure, or physical validation is claimed here.

## Source layout

| Path | Role |
|---|---|
| `rtl/axi_spi_core.sv` | AXI frontend, register decode, FIFO control, explicit transaction tracking, and DMA integration |
| `rtl/spi_master.sv` | SPI shifting, clock generation, and CS hold between bytes |
| `rtl/sync_fifo.sv` | Parameterized synchronous FIFO |
| `rtl/byte_ram.sv` | Byte-wide RAM with synchronous read |
| `rtl/spi_dma.sv` | Local TX/RX RAM transfer engine |
| `tb/` | Simulation testbenches and byte vectors |
| `scripts/generate_vectors.py` | Deterministic test-vector generation |

Some supplementary documents describe an earlier design version. In particular, the older five-register specification does not cover explicit transactions or DMA; use this register map alongside the current RTL for those features.
