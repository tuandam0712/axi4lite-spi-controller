# AXI4-Lite → SPI Master Controller

Đàm Phúc Tuấn — 23CE086 · Dương Thanh Trường — 23CE083

CE2031 Digital IC Design. Đây là project riêng để đặt vào `D:\DoAn\TKIC\axi_spi`; không ghi đè lab1/lab2 hoặc QSF cũ.

## Những gì đã có

- AXI4-Lite slave 32 bit, địa chỉ 8 bit, AW/W độc lập; một write và một read outstanding.
- SPI master 8 bit, MSB-first, đủ CPOL/CPHA 0–3, full duplex; CS nhả giữa từng byte.
- TX/RX FIFO mặc định 8 byte, tham số hóa depth từ 2 trở lên.
- Python tạo vector; TB tự kiểm tra AXI, SPI slave độc lập, FIFO và bộ demo DE2.
- Wrapper DE2: nút nhấn được đồng bộ/debounce, AXI master FSM, HEX và đèn kết quả.
- Project Quartus II với top `de2_demo`, device EP2C35F672C6, chân và SDC cơ bản.

RTL và TB đã chạy Icarus Verilog 11.0 trong môi trường tạo project. Questa, Quartus, TimeQuest và board thật **chưa được chạy ở đây**. Xem `docs/verification.md` để biết phạm vi kiểm tra và việc còn lại.

## Chạy Questa trước

Giải nén vào `D:\DoAn\TKIC\axi_spi` rồi gõ trong Transcript:

```tcl
do D:/DoAn/TKIC/axi_spi/scripts/run_questa.do
```

Script biên dịch vào library riêng `axi_spi_work`, thêm waveform và chạy `tb_axi_spi`. Kết quả cần có `PASS: ... 1016 SPI bytes`. Không dùng `-novopt`.

Để chạy cả ba TB từ terminal có `vsim` trong PATH:

```powershell
vsim -c -do D:/DoAn/TKIC/axi_spi/scripts/run_questa_batch.do
```

Để xem wrapper sau khi đã compile:

```tcl
quit -sim
vsim -voptargs=+acc axi_spi_work.tb_de2_demo
add wave -r sim:/tb_de2_demo/*
run -all
```

Chụp waveform mỗi mode: `cs_n`, `sclk`, `mosi`, `miso`, `expected_tx`, `slave_byte`, `rdata`; zoom một hoặc hai byte để thấy rõ cạnh và byte dữ liệu.

## Chạy Icarus (tùy chọn)

Trong thư mục project, với Python 3 và Icarus trong PATH:

```powershell
python scripts/run_iverilog.py
```

Hoặc đặt biến môi trường `IVERILOG`, `VVP` là đường dẫn executable. Log ghi vào `build/regression.log`. Không cần tạo lại vector khi chạy Questa; `tb/vectors.hex` đã có sẵn. Để tạo lại: `python scripts/generate_vectors.py`.

## Quartus và DE2

1. Mở `quartus/axi_spi_de2.qpf`, xác nhận top `de2_demo` và device Cyclone II EP2C35F672C6.
2. Start Compilation. Xử lý errors và đọc warnings; đặc biệt kiểm tra SDC có match đúng các register đồng bộ. Cần lưu Flow Summary, Fitter Resource Usage và TimeQuest Setup/Hold Summary.
3. Timing clock chính là 50 MHz. SDC có giả định budget I/O 5 ns cho loopback, chưa phải số đo board. Không coi timing đã đóng chỉ vì compile thành công; xem thêm `docs/hardware.md`.
4. File nạp nằm ở `quartus/output_files/axi_spi_de2.sof`. Tools → Programmer → Hardware Setup → USB-Blaster, chọn JTAG, Add File `.sof`, tick Program/Configure, Start.
5. Làm demo theo `docs/hardware.md`; jumper MOSI–MISO dùng chân **header DE2 thật**, không phải tên chân BGA.

## Cấu trúc

| Thư mục | Nội dung |
|---|---|
| rtl | FIFO, SPI engine, AXI core, DE2 wrapper |
| tb | Ba TB self-checking và 1016 vector |
| scripts | Questa GUI/batch, Icarus runner, Python vector generator |
| quartus | QPF, QSF, SDC |
| docs | Spec, sơ đồ, kết quả mô phỏng, hướng dẫn board |

## Phần còn lại để thành bản final

Chạy lại Questa trên máy anh; compile/đọc timing ở Quartus; chạy DE2 thật và lưu ảnh; cập nhật các số LE, Fmax, slack từ report thực tế; ghép báo cáo theo form IEEE của thầy. Đề cương và project này chưa thay cho báo cáo final đã có kết quả phần cứng.
