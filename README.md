# GAN-MIND: GAN with MLP Architecture for Intensive Digit Identification
MLP GAN implementation for mnist generator and discriminator.

# Contributors (Name/NIM) :
Dennis Hubert       / 13222018

I Made Medika Surya / 13222021

William Anthony     / 13223048

## CARA RUN VIA TCL SCRIPT

1. Buka "Vivado Tcl Shell" (atau jalankan `settings64.bat`) supaya perintah `vivado` tersedia.
2. Dari root repo jalankan:

```
cd D:/GANMIND/GANMIND
vivado -mode batch -source vivado_all/setup_project_sources.tcl
vivado -mode batch -source vivado_all/analyze_timing.tcl
```

`setup_project_sources.tcl` akan memastikan `pipelined_mac.v` dan seluruh file berat/ bias `.hex` sudah terdaftar di project serta menyamakan `HEX_DATA_ROOT`. Setelah itu `analyze_timing.tcl` bisa langsung re-run synth/impl dan membuat report timing.


## PYNQ/Vivado Integration Notes

- Use `src/top/gan_serial_axi_wrapper.v` as the exported top for Vivado. It wraps `gan_serial_top` with:
	- AXI4-Lite control (start/busy/done status + discriminator scores).
	- AXI-Stream slave input (`tdata[0]` carries each serialized pixel bit).
	- AXI-Stream master output streaming the 784×16-bit generated frame (check `FRAME_WORDS` register for depth).
- Register map (offsets in bytes):
	- `0x00 CTRL` bit0 = write 1 to launch inference (auto-clears next cycle).
	- `0x04 STATUS` bit0 busy, bit1 done (sticky until the next start), bit2 frame loader ready, bit3 generated frame valid, bit4 fake score says "real", bit5 real score says "real".
	- `0x08` fake score (signed Q8.8), `0x0C` real score, `0x10` constant 784 (words streamed per frame).
- Vivado flow:
	1. Add the entire `src` tree, set include dirs to `src/top`, `src/interfaces`, `src/generator`, `src/discriminator`, `src/layers`, `src/fifo`.
	2. Set the project top to `gan_serial_axi_wrapper` (not `gan_serial_top`).
	3. Package the wrapper as a custom IP, drop it into a block design with `processing_system7` (or UltraScale equivalent), and connect:
		 - AXI4-Lite interface → PS master GP port.
		 - Pixel AXI-Stream slave → AXI DMA/VDMA MM2S channel feeding serialized MNIST bits.
		 - Frame AXI-Stream master → AXI DMA S2MM channel (or BRAM controller) to capture the 784 samples and scores in software.
	4. Export the block design wrapper (`.xsa`) and bitstream for the PYNQ overlay.

With this wrapper in place, Vivado no longer reports the IO-related DRC violations because all external connectivity routes through AXI buses instead of discrete top-level pins.
