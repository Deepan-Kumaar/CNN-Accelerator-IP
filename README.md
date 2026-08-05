# CNN Accelerator IP

> **⚠️ Project Status: Work in Progress**  
> This project is currently under active development. Core RTL modules are functional and passing simulation, but several key features (software driver, im2col address generator, per-tile requantization, FPGA bring-up) are not yet implemented. See [Project Status & Roadmap](#project-status--roadmap) for details.

A memory-mapped Convolutional Neural Network (CNN) accelerator IP integrated into a RISC-V SoC built around the [lowRISC Ibex](https://github.com/lowRISC/ibex) core. The accelerator provides an INT8/INT16 quantized MAC datapath with ReLU and 2×2 max-pooling, on-chip input/weight/output buffers, and an AXI4-Lite control plane, connected to the rest of the SoC through a PULP `axi_xbar`.

The repository contains the SystemVerilog RTL for the IP and the SoC, a Python golden model, self-checking testbenches, and build/simulation scripts for both ModelSim/QuestaSim and Verilator.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Directory Layout](#directory-layout)
- [Address Map](#address-map)
- [Build & Simulation](#build--simulation)
- [Testbenches](#testbenches)
- [Software Golden Model](#software-golden-model)
- [Toolchain Requirements](#toolchain-requirements)
- [Project Status & Roadmap](#project-status--roadmap)
- [References](#references)
- [License](#license)

---

## Features

- **Tightly-coupled CNN accelerator** mapped into the Ibex memory map at `0x1000_0000`.
- **Quantized datapath** supporting INT8 (single-cycle) and INT16 (two-cycle packed) MAC operations.
- **Parallel PE array** — `PE_COUNT = 4` output channels computed in parallel, each with a 32-bit accumulator.
- **On-chip buffers** for activations, weights, and partial outputs (`BUF_ADDR_W = 12` → 4 K × 32-bit words per buffer).
- **AXI4 DMA controller** that streams input/weight tiles in and writes results back to system memory.
- **Activation pipeline** with optional ReLU and 2×2 max-pooling over four pooled patches.
- **Configurable job descriptor** for kernel size, mode, ReLU/pool enable, and patch stride.
- **AXI4-Lite control/status register slave** with start, busy/done/err flags, IRQ enable, and IRQ clear.
- **Ibex-based SoC** with 128 KB data SRAM, 128 KB instruction SRAM, and a 2-master / 2-slave AXI crossbar.
- **Software golden model** in Python that generates test vectors and expected outputs, which the RTL self-checking testbench compares against.
- **Build flows for both ModelSim/QuestaSim (`make`)** and **Verilator (`./scripts/sim_verilator.sh`)**.

---

## Architecture

```text
                 +----------------------------+
                 |          Ibex Core         |
                 |   (RV32IMC, lowRISC)       |
                 +-------------+--------------+
                               |
                       AXI4-Lite slave
                               |
                       +-------v-------+
                       |   AXI xbar    |   <-- 2 masters, 2 slaves
                       +---+-------+---+
                           |       |
       +-------------------+       +----------------------+
       |                                                  |
+------v------+   AXI4 full                       AXI4-Lite slave
|  CNN DMA    |                                            |
|  master     |                                  +---------v--------+
+------+------+                                  |  CNN Accelerator |
       |                                         |  (cnn_accel_top) |
       | AXI                                    |                   |
       |                                         |  - register_ctrl  |
       |                                         |  - dma_controller |
       |                                         |  - mac_array      |
       |                                         |  - pe_x N         |
       |                                         |  - bram in/wgt/out|
+------v------+         +--------------+         +-------------------+
| Data SRAM   |  <----> | On-chip BRAM | <----->
| (tc_sram)   |         | buffers      |
+-------------+         +--------------+
```

### Block-level summary

| Module | File | Responsibility |
| --- | --- | --- |
| `cnn_accel_pkg` | [rtl/cnn_accel_pkg.sv](rtl/cnn_accel_pkg.sv) | Compile-time parameters, register map, enums. |
| `cnn_accel_top` | [rtl/cnn_accel_top.sv](rtl/cnn_accel_top.sv) | Top-level accelerator wrapper, register-facing interface. |
| `register_ctrl` | [rtl/register_ctrl.sv](rtl/register_ctrl.sv) | AXI4-Lite register file, status/IRQ logic. |
| `dma_controller` | [rtl/dma_controller.sv](rtl/dma_controller.sv) | AXI4 master, fills/drains the on-chip buffers. |
| `mac_array` | [rtl/mac_array.sv](rtl/mac_array.sv) | `PE_COUNT`-wide MAC array, reduction across `K`. |
| `processing_element` | [rtl/processing_element.sv](rtl/processing_element.sv) | Single signed INT8 multiply-accumulate unit. |
| `bram` | [rtl/bram.sv](rtl/bram.sv) | 32-bit-wide single-port BRAM used for the input/weight/output buffers. |
| `instr_mem` | [rtl/instr_mem.sv](rtl/instr_mem.sv) | Instruction memory wrapper for Ibex. |
| `soc_top` | [rtl/soc_top.sv](rtl/soc_top.sv) | Full SoC: Ibex, AXI xbar, SRAMs, CNN accelerator, IRQ wiring. |
| `ibex_top` | [rtl/ibex_top.sv](rtl/ibex_top.sv) | Ibex core wrapper (from lowRISC, fetched via Bender). |

---

## Directory Layout

```text
.
├── Bender.yml                 # Dependency manifest (axi, ibex)
├── Makefile                   # ModelSim/QuestaSim build & run
├── README.md
├── build/                     # Generated — ModelSim/QuestaSim work library
├── docs/
│   ├── cnn_acc_ip.md          # High-level IP plan
│   └── cnn_specs.md           # Spec notes
├── rtl/                       # SystemVerilog sources
│   ├── bram.sv
│   ├── cnn_accel_pkg.sv
│   ├── cnn_accel_top.sv
│   ├── dma_controller.sv
│   ├── ibex_top.sv
│   ├── instr_mem.sv
│   ├── mac_array.sv
│   ├── processing_element.sv
│   ├── register_ctrl.sv
│   ├── soc_top.sv
│   └── templates/             # Earlier scaffolding (kept for reference)
├── scripts/
│   ├── sim_verilator.sh       # Verilator build + run
│   └── stress_test.sh         # Re-runs the testbench N times
├── sw/
│   ├── golden_model.py        # Python reference model & vector generator
│   └── tb_soc_top_verilator.cpp
└── tb/                        # Testbenches
    ├── tb_cnn_accel.sv
    ├── tb_cnn_accel_full.sv
    ├── tb_cnn_accel_single_job.sv
    ├── tb_dma_bram_mc.sv
    ├── tb_mac_array.sv
    ├── tb_register_dma.sv
    ├── tb_soc_top.sv
    └── vectors/               # Generated by sw/golden_model.py
```

---

## Address Map

The full SoC (`soc_top`) places the accelerator at `0x1000_0000` and the SRAMs in the bottom 256 KB of the address space.

| Region | Address | Size | Description |
| --- | --- | --- | --- |
| Data SRAM | `0x0000_0000 – 0x0001_FFFF` | 128 KB | Main data memory (`tc_sram`). |
| Instr SRAM | `0x0002_0000 – 0x0003_FFFF` | 128 KB | Ibex instruction memory. |
| CNN accel regs | `0x1000_0000 – 0x1000_00FF` | 256 B | AXI4-Lite slave register file. |

### CNN accelerator register file (byte offsets)

| Offset | Name | Description |
| --- | --- | --- |
| `0x00` | `CTRL` | `[0] START`, `[1] SOFT_RST`. |
| `0x04` | `STATUS` | `[0] BUSY`, `[1] DONE`, `[2] ERROR` (sticky). |
| `0x08` | `IRQ_EN` | `[0] DONE_IE`. |
| `0x0C` | `IRQ_CLR` | Write `1` to clear `DONE`/`ERROR`. |
| `0x10` | `DMA_SRC` | System-memory source address for the current DMA beat. |
| `0x14` | `DMA_SEL` | `[1:0]` buffer select: `0`=input, `1`=weight, `2`=output. |
| `0x18` | `DMA_LEN` | Transfer length in 32-bit words. |
| `0x1C` | `DMA_DIR` | `0` = mem→buf (load), `1` = buf→mem (store). |
| `0x20` | `DMA_START` | Write `1` to kick off the configured DMA op. |
| `0x24` | `GEMM_M` | Number of output rows (im2col rows). |
| `0x28` | `GEMM_K` | Reduction depth (im2col row length). |
| `0x2C` | `GEMM_NTILES` | Number of `PE_COUNT`-wide N tiles to sweep. |
| `0x30` | `QUANT_SCALE` | Q0.16 fixed-point requant multiplier. |
| `0x34` | `QUANT_SHIFT` | Right-shift applied after the multiply. |
| `0x38` | `QUANT_ZP` | Output zero point (added post-shift). |
| `0x3C` | `ACT_CTRL` | `[0] RELU_EN`, `[1] POOL_EN` (2×2 max pool). |
| `0x40` | `OUT_ELEMS` | RO: number of valid 32-bit words written to output buffer. |

---

## Build & Simulation

Dependencies (Ibex and AXI) are pulled by [Bender](https://github.com/pulp-platform/bender). `Bender.yml` is the source of truth for versions:

```yaml
dependencies:
  axi:  { git: "https://github.com/pulp-platform/axi.git",  version: 0.38.0 }
  ibex: { git: "https://github.com/lowRISC/ibex.git",       rev:    "95b85ddd..." }
```

### One-time setup

```bash
# Install Bender (https://github.com/pulp-platform/bender)
# Then from the repo root:
make update
```

### ModelSim / QuestaSim

```bash
make all          # gen + compile-modelsim + run-modelsim
# or step-by-step
make gen                       # regenerate test vectors via sw/golden_model.py
make compile-modelsim          # vlib + vlog
make run-modelsim              # vsim -c -do "run -all; quit -f"
make open-modelsim             # open the GUI waveform viewer
```

If the ModelSim binaries are not on your `PATH`:

```bash
make sim VSIM=/path/to/vsim VLOG=/path/to/vlog VLIB=/path/to/vlib
```

A passing run prints something like:

```text
PASS: outputs match software golden model.
ALL TESTS PASSED
```

### Verilator

```bash
./scripts/sim_verilator.sh
```

The script compiles the design with Verilator, enables tracing (`--trace`), and produces the executable `build/verilator/obj_dir/Vtb_soc_top`.

### Stress test

Re-runs the full testbench N times to flush out intermittent issues:

```bash
./scripts/stress_test.sh   # defaults to 10 runs
```

### Clean

```bash
make clean                  # removes build/, vendor/, .bender/, generated vectors,
                            # transcript, vsim.wlf
```

---

## Testbenches

| Testbench | File | Focus |
| --- | --- | --- |
| `tb_soc_top` | [tb/tb_soc_top.sv](tb/tb_soc_top.sv) | Full SoC, end-to-end against Python golden model. |
| `tb_cnn_accel_full` | [tb/tb_cnn_accel_full.sv](tb/tb_cnn_accel_full.sv) | Accelerator unit test with multi-job descriptors. |
| `tb_cnn_accel_single_job` | [tb/tb_cnn_accel_single_job.sv](tb/tb_cnn_accel_single_job.sv) | Single-job smoke test. |
| `tb_cnn_accel` | [tb/tb_cnn_accel.sv](tb/tb_cnn_accel.sv) | Legacy accelerator TB. |
| `tb_mac_array` | [tb/tb_mac_array.sv](tb/tb_mac_array.sv) | PE array in isolation. |
| `tb_dma_bram_mc` | [tb/tb_dma_bram_mc.sv](tb/tb_dma_bram_mc.sv) | DMA ↔ BRAM streaming. |
| `tb_register_dma` | [tb/tb_register_dma.sv](tb/tb_register_dma.sv) | Register file + DMA descriptor programming. |

All testbenches use a self-checking style: the testbench loads vectors produced by `sw/golden_model.py`, drives the DUT, and compares outputs to the expected file.

---

## Toolchain Requirements

- **Python 3.8+** — for the golden model / vector generator.
- **Bender** — to vendor the `axi` and `ibex` dependencies.
- **ModelSim / QuestaSim** — for the primary `make` flow (`vlib`, `vlog`, `vsim`).
- **Verilator 5.x+** — for `./scripts/sim_verilator.sh`.
- **A C++14 compiler** — used by the Verilator-generated harness.
- A RISC-V toolchain is **not** required to run the SystemVerilog testbenches; it is only needed once firmware for the Ibex core is added.

---

## References

- [lowRISC Ibex core](https://github.com/lowRISC/ibex)
- [PULP-platform AXI](https://github.com/pulp-platform/axi)
- [PULP-platform Bender](https://github.com/pulp-platform/bender)
- Project design notes: [docs/cnn_acc_ip.md](docs/cnn_acc_ip.md), [docs/cnn_specs.md](docs/cnn_specs.md)

---

## License

TBD. Unless noted otherwise in individual source files, the contents of this repository are © 2026 Deepan Kumaar Adaikkalam.