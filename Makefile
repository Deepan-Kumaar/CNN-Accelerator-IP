TOP=tb_soc_top
WORKLIB=build/work
VLOG ?= vlog
VSIM ?= vsim
VLIB ?= vlib
AXI_PATH = $(shell bender path axi)




SRC_FILES = $(shell bender script flist-plus -t synthesis )


.PHONY: all gen  compile-modelsim run-modelsim clean com open-modelsim

all: gen compile-modelsim run-modelsim

update:
	bender vendor init
	bender update
	cd $(AXI_PATH) && bender vendor init && cd -

gen:
	python3 sw/golden_model.py

compile-modelsim:
	mkdir -p build
	rm -rf $(WORKLIB)
	$(VLIB) $(WORKLIB)
	$(VLOG) -sv -work $(WORKLIB) $(SRC_FILES)

com:
	$(VLOG) -sv -work $(WORKLIB) $(SRC_FILES)

run-modelsim:
	$(VSIM) -c -quiet -lib $(WORKLIB) $(TOP) -do "run -all; quit -f"

open-modelsim:
	$(VSIM) -lib $(WORKLIB) -onfinish final $(TOP)    -do "add wave *;add wave -position insertpoint \
	sim:/tb_soc_top/dut/cnn_accel_top_inst/u_bram_output/mem;log * -r;run -all;" 

clean:
	rm -rf build
	rm -rf vendor
	rm -rf .bender
	rm -f tb/vectors/mem_init.hex tb/vectors/expected.hex
	rm vsim.wlf transcript
