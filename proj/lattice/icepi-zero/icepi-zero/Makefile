OUTPUT := bitstream
PACKAGE := CABGA256

TOP_MODULE = icepi_zero
TOP_MODULE_FILE = ../../../../hdl/top/$(TOP_MODULE)_top.v

VERILOG_FILES = \
  $(TOP_MODULE_FILE) \
  ../../../../hdl/RISC5Top.OStation.v \
  ../../../../hdl/RISC5.v \
  ../../../../hdl/PROM.v \
  ../../../../hdl/cache_controller.v \
  ../../../../hdl/sdram.v \
  ../../../../hdl/PS2.v \
  ../../../../hdl/mousem.v \
  ../../../../hdl/RS232R.v \
  ../../../../hdl/RS232T.v \
  ../../../../hdl/SPI.v \
  ../../../../hdl/Multiplier.v \
  ../../../../hdl/Divider.v \
  ../../../../hdl/FPAdder.v \
  ../../../../hdl/FPDivider.v \
  ../../../../hdl/FPMultiplier.v \
  ../../../../hdl/VID.OStation.v \
  ../../../../hdl/lattice/bram32bit.v \
  ../../../../hdl/bram_true2p_2clk.v \
  ../../../../hdl/vqueue.v \
  ../../../../hdl/lattice/ecp5pll.sv \
  ../../../../hdl/hex/osd.v \
  ../../../../hdl/hex/hex_decoder.v \
  ../../../../hdl/dvi/vga.v \
  ../../../../hdl/dvi/vga2dvid.v \
  ../../../../hdl/dvi/tmds_encoder.v \
  ../../../../hdl/usb/usb_hid_host.v \
  ../../../../hdl/usb/usb_hid_host_rom.v \

# synthesis options
# YOSYS_OPTIONS = -abc9
# NEXTPNR_OPTIONS = --timing-allow-fail

all: debug

.SECONDARY: $(OUTPUT).json $(OUTPUT).config

bitstream.json: $(VERILOG_FILES)
	rm -f $(OUTPUT).bit $(OUTPUT).config $(OUTPUT).json
	yosys -p 'synth_ecp5 -abc9 -top $(TOP_MODULE) -json $@' $^

bitstream.config: bitstream.json icepi-zero.lpf
	nextpnr-ecp5 --25k --timing-allow-fail --package $(PACKAGE) --lpf icepi-zero.lpf --json $< --textcfg $@ # 2> log.txt
	# cat log.txt | grep Device -A 28

bitstream.bit: bitstream.config
	ecppack $< $@

build: $(OUTPUT).bit

debug: build
	openFPGALoader -cft231X --pins=7:3:5:6 $(OUTPUT).bit

install: build
	openFPGALoader -cft231X --pins=7:3:5:6 $(OUTPUT).bit --write-flash

install-bitstream:
	openFPGALoader -cft231X --pins=7:3:5:6 $(OUTPUT).bit --write-flash

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-WIDTHEXPAND $(VERILOG_SOURCES)

help:
	echo "Usage: make [option]"
	echo "Options:"
	echo "- install: install to flash"
	echo "- debug: install to chip's temp memory (bitstream lost on power loss)"
	echo "- build: builds the bitstream"
	echo "- clean: delete all temparary files"

clean:
	rm -f $(OUTPUT).bit $(OUTPUT).config $(OUTPUT).json

.PHONY: build clean install
