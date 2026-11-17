# Verification record

Environment: Icarus Verilog 11.0, Python 3; creation date 2026-10-06. All tests fail with `$fatal` and a nonzero Icarus exit code. Questa batch also checks each top's `test_passed` flag before declaring success.

| Testbench | Checks |
|---|---|
| tb_axi_spi | Independent SPI slave; 16 directed +1000 Python-seeded random full-duplex vectors; all four modes; MOSI order, 8 sample/16 SCLK edges per byte; RX bytes; 82/83-cycle completion/enqueue at D=5; AW-before-W/W-before-AW/together; concurrent read/write; stalled B/R stability; partial/zero WSTRB; invalid/misaligned/RO accesses; empty-RX read; full-TX write; RX-full pause/resume; busy divider reject; reset during SPI/partial AW |
| tb_de2_demo | 00/FF/AA/55 in all four modes; independent AXI master FSM; simulated physical MOSI–MISO loopback; persistent PASS; deliberate mismatch FAIL; reset clears result |
| tb_boundaries | Depth3 FIFO order/full/empty/overflow/underflow, simultaneous push/pop and pointer wrap; D=65535 complete 8-bit mode3 loopback and 65535-cycle edge spacing |

Actual concise transcript is included as `docs/regression.log`. Inverting the sampled MISO bit in a temporary RTL copy produced an RX mismatch and exit code 1; the shipped RTL was unaffected. This is directed/procedural regression, not formal proof or an exhaustive AXI compliance suite. No line/toggle/functional coverage percentage has been measured. The Python model supplies deterministic independent TX/RX bytes, not a full AXI/FIFO cycle model.

Outstanding acceptance gates: rerun Questa (scripts provided but not executed here), Quartus synthesis/fitter, 50-MHz setup/hold closure with reviewed I/O assumptions, and DE2 board tests. Complete these before describing this as a physically validated final design.
