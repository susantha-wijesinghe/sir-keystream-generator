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
#   make sim      run the testbenches with Icarus Verilog
#                 (core on kat/, core on 100 random vectors, XOR wrapper)
#   make clean    remove build/

PYTHON   ?= python3
CC       ?= cc
CFLAGS   ?= -O2 -Wall -Wextra
IVERILOG ?= iverilog
VVP      ?= vvp

BUILD := build
RANDOM_N    ?= 100
RANDOM_SEED ?= 1

.PHONY: all kat check sim sim-core sim-random sim-wrapper clean

all: check sim

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/sir: model/sir.c | $(BUILD)
	$(CC) $(CFLAGS) -o $@ $<

kat:
	$(PYTHON) model/gen_kat.py

check: $(BUILD)/sir
	$(PYTHON) model/check_models.py $(BUILD)/sir

sim: sim-core sim-random sim-wrapper

$(BUILD)/tb_sir_core.vvp: rtl/sir_core.v tb/tb_sir_core.v | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $@ rtl/sir_core.v tb/tb_sir_core.v

sim-core: $(BUILD)/tb_sir_core.vvp
	$(VVP) -n $(BUILD)/tb_sir_core.vvp

# Core against model/sir.py on RANDOM_N random key/IV pairs, 64 bytes each
sim-random: $(BUILD)/tb_sir_core.vvp
	$(PYTHON) model/gen_kat.py --random $(RANDOM_N) --seed $(RANDOM_SEED) --mem $(BUILD)/random.mem
	$(VVP) -n $(BUILD)/tb_sir_core.vvp +kat=$(BUILD)/random.mem +nv=$(RANDOM_N)

sim-wrapper: | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $(BUILD)/tb_sir_xor_wrapper.vvp \
		rtl/sir_core.v rtl/sir_xor_wrapper.v tb/tb_sir_xor_wrapper.v
	$(VVP) -n $(BUILD)/tb_sir_xor_wrapper.vvp

clean:
	rm -rf $(BUILD)
