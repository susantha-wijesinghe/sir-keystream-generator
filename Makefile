#
# Makefile
# Builds the C model, regenerates the KAT files, and runs the model checks and RTL simulations.
#
# Author      : Prof. W.A. Susantha Wijesinghe
# Email       : susantha@wyb.ac.lk
# Website     : susanthawijesinghe.com
# Date        : 24/11/2026
#
# Copyright   : © 2026  W.A. Susantha Wijesinghe
# License     : MIT (see LICENSE)
#
# Targets:
#   make          run everything (check + sim)
#   make kat      regenerate kat/ from model/sir.py
#   make check    compare Python model, C model and kat/
#   make sim      run both testbenches with Icarus Verilog
#   make clean    remove build/

PYTHON   ?= python3
CC       ?= cc
CFLAGS   ?= -O2 -Wall -Wextra
IVERILOG ?= iverilog
VVP      ?= vvp

BUILD := build

.PHONY: all kat check sim sim-core sim-wrapper clean

all: check sim

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/sir: model/sir.c | $(BUILD)
	$(CC) $(CFLAGS) -o $@ $<

kat:
	$(PYTHON) model/gen_kat.py

check: $(BUILD)/sir
	$(PYTHON) model/check_models.py $(BUILD)/sir

sim: sim-core sim-wrapper

sim-core: | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $(BUILD)/tb_sir_core.vvp rtl/sir_core.v tb/tb_sir_core.v
	$(VVP) -n $(BUILD)/tb_sir_core.vvp

sim-wrapper: | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $(BUILD)/tb_sir_xor_wrapper.vvp \
		rtl/sir_core.v rtl/sir_xor_wrapper.v tb/tb_sir_xor_wrapper.v
	$(VVP) -n $(BUILD)/tb_sir_xor_wrapper.vvp

clean:
	rm -rf $(BUILD)
