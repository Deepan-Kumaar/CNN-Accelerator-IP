TOOLCHAIN ?= riscv64-unknown-elf
CC := $(TOOLCHAIN)-gcc
OBJCOPY := $(TOOLCHAIN)-objcopy

PYTHON ?= python3

SRC_DIR := .
DRIVER_DIR := drivers
OUT_DIR := outputs

TARGET := $(OUT_DIR)/cnn
ELF := $(TARGET).elf
BIN := $(TARGET).bin
MEM := cnn_mem.mem

COMMON_FLAGS := -std=c11 -ffreestanding -nostdlib -nostartfiles -Wall -Wextra -Werror
CPU_FLAGS := -march=rv32imc -mabi=ilp32
INCLUDES := -I. -I$(DRIVER_DIR)

OBJS := \
	$(OUT_DIR)/crt0.o \
	$(OUT_DIR)/main.o \
	$(OUT_DIR)/cnn.o

.PHONY: all clean mem bin elf

all: $(MEM)

mem: $(MEM)

bin: $(BIN)

elf: $(ELF)

$(OUT_DIR):
	mkdir -p $@

$(OUT_DIR)/crt0.o: crt0.S | $(OUT_DIR)
	$(CC) $(COMMON_FLAGS) $(CPU_FLAGS) $(INCLUDES) -c $< -o $@

$(OUT_DIR)/main.o: main.c | $(OUT_DIR)
	$(CC) $(COMMON_FLAGS) $(CPU_FLAGS) $(INCLUDES) -c $< -o $@

$(OUT_DIR)/cnn.o: $(DRIVER_DIR)/cnn.c $(DRIVER_DIR)/cnn.h $(DRIVER_DIR)/cnn_regs.h | $(OUT_DIR)
	$(CC) $(COMMON_FLAGS) $(CPU_FLAGS) $(INCLUDES) -c $< -o $@

$(ELF): $(OBJS) linker.ld
	$(CC) $(COMMON_FLAGS) $(CPU_FLAGS) -T linker.ld -Wl,-Map=$(TARGET).map -o $@ $(OBJS)

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(MEM): $(BIN) bin_to_mem.py
	cd $(CURDIR) && $(PYTHON) bin_to_mem.py

clean:
	rm -f $(OUT_DIR)/crt0.o $(OUT_DIR)/main.o $(OUT_DIR)/cnn.o
	rm -f $(ELF) $(BIN) $(TARGET).map $(MEM)
