# ECE32 : RISC-V SoC with Custom DSP Accelerators

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Verilog Linting](https://github.com/your-username/riscv-dsp-soc/actions/workflows/lint.yml/badge.svg)](https://github.com/your-username/riscv-dsp-soc/actions/workflows/lint.yml)
[![Simulation Tests](https://github.com/your-username/riscv-dsp-soc/actions/workflows/simulation.yml/badge.svg)](https://github.com/your-username/riscv-dsp-soc/actions/workflows/simulation.yml)
[![FPGA Build](https://github.com/your-username/riscv-dsp-soc/actions/workflows/fpga_build.yml/badge.svg)](https://github.com/your-username/riscv-dsp-soc/actions/workflows/fpga_build.yml)

## 1. Project Overview

This project implements a 32-bit RISC-V based System-on-Chip (SoC) augmented with custom Digital Signal Processing (DSP) accelerators. The primary goal is to create a flexible and extensible platform for applications requiring both general-purpose computation and specialized signal processing capabilities, such as those found in wireless communications, audio processing, and edge machine learning.

The current SoC features a simple rv32i core, instruction and data memories, a bus interconnect, and two custom DSP units:
*   A 1D Convolution accelerator.
*   A Vector Dot Product accelerator.

The system is designed to be simulatable using Verilator and synthesizable for FPGAs (targeting Xilinx Vivado).

## 2. Features

*   **RISC-V Core:** A basic 32-bit integer CPU (RV32I subset).
*   **Memory System:** Separate instruction and data memories (configurable sizes).
*   **Bus Interconnect:** Connects CPU, memories, and DSP accelerators. Supports multiple masters and slaves with basic priority-based arbitration.
*   **1D Convolution DSP:** Hardware accelerator for 1D convolution operations, configurable via AXI-Lite.
*   **Dot Product DSP:** Hardware accelerator for vector dot product operations, configurable via AXI-Lite.
*   **AXI-Lite Control:** DSP accelerators are controlled by the CPU using memory-mapped AXI-Lite registers.
*   **Simulation Environment:**
    *   Verilator-based simulation setup using C++ testbenches.
    *   CMake for managing Verilator builds.
    *   VCD trace generation for debugging.
*   **FPGA Synthesis Flow:**
    *   Makefile-driven flow targeting Xilinx Vivado.
    *   Support for synthesis, implementation, and bitstream generation.
*   **Modularity:** Designed with distinct modules for CPU, memory, bus, and DSP units to encourage extension and modification.
*   **Open Source:** Licensed under the MIT License.

## 3. Architecture

The SoC integrates a RISC-V processor core with memory subsystems and custom DSP accelerators through a central bus interconnect.

```
[Placeholder for a high-level block diagram of the SoC]
e.g.,
+-----------------+      +----------------------+      +--------------------+
|   RISC-V CPU    |<---->|                      |<---->|  DSP_CONV1D (AXI)  |
| (RV32I)         |      |   Bus Interconnect   |      +--------------------+
+-----------------+      | (CPU, ConvDSP, DP_DSP|
      ^            <---->|  Masters to Mem/Peri)|      +--------------------+
      |                  |                      |<---->| DSP_DOT_PRODUCT(AXI)|
      |                  +----------------------+      +--------------------+
      |                        ^      |
      |                        |      |
      |   (Instruction Fetch)  |      | (Data Access)
      |                        |      |
      v                        v      v
+-----------------+      +-----------------+
| Instruction Mem |      | Data Memory     |
+-----------------+      +-----------------+
```

### 3.1. RISC-V CPU

*   **ISA:** Implements a subset of the RV32I base integer instruction set.
*   **Pipeline:** A simple pipeline structure (details to be added based on actual CPU design, e.g., 3-stage or 5-stage). For this project, it's a conceptual CPU whose datapath and control unit were built incrementally.
*   **Memory Access:** Communicates with instruction and data memories via the bus interconnect. Supports stalling for multi-cycle memory operations via an acknowledgment signal from the bus.

### 3.2. Memory System

*   **Instruction Memory (`INST_MEM`):** Stores the program executed by the RISC-V core. Implemented as a simple ROM-like block, initialized at simulation start (e.g., with NOPs or a pre-loaded program).
*   **Data Memory (`DATA_MEM`):** A general-purpose RAM used for data storage. Accessible by both the CPU and the DSP accelerators via the bus interconnect.

### 3.3. Bus Interconnect (`BUS_INTERCONNECT`)

*   **Functionality:** Manages data flow between masters (CPU, DSPs) and slaves (Data Memory, DSP control registers).
*   **Address Decoding:** Routes requests to the appropriate slave based on the memory address.
*   **Arbitration:** Implements a simple priority-based arbitration scheme when multiple masters request access to the same slave (e.g., DATA_MEM). Current priority: CPU > Convolution DSP > Dot Product DSP.
*   **Interfaces:**
    *   CPU-side: Custom memory request interface.
    *   Peripheral-side: AXI-Lite for DSP control registers, custom interface for Data Memory.

### 3.4. DSP Accelerators

Both DSP units are designed as peripherals on the main bus, with AXI-Lite slave interfaces for control/status registers and their own memory master capabilities to fetch/store data from/to `DATA_MEM`.

```
[Placeholder for a diagram showing CPU -> AXI-Lite -> DSP_Control_Reg]
[Placeholder for a diagram showing DSP -> Memory_Master_IF -> DATA_MEM]
```

#### 3.4.1. 1D Convolution DSP (`DSP_CONV1D`)

*   **Functionality:** Performs 1D convolution: `Output[i] = sum(Input[i+j] * Kernel[j])`.
*   **Configuration (via AXI-Lite):**
    *   Base addresses for Input Data, Kernel, and Output Data buffers in `DATA_MEM`.
    *   Lengths of the Input Data array and the Kernel.
    *   Control register to start operation and enable interrupts.
    *   Status register to indicate busy, done, or error states.
*   **Operation:**
    1.  CPU configures the DSP and issues a start command.
    2.  DSP autonomously fetches input data and kernel values from `DATA_MEM`.
    3.  Performs Multiply-Accumulate (MAC) operations.
    4.  Stores results back to `DATA_MEM`.
    5.  Notifies CPU of completion via status register (and optional interrupt).

#### 3.4.2. Dot Product DSP (`DSP_DOT_PRODUCT`)

*   **Functionality:** Calculates the dot product of two vectors: `Result = sum(VectorA[j] * VectorB[j])`.
*   **Configuration (via AXI-Lite):**
    *   Base addresses for Vector A and Vector B in `DATA_MEM`.
    *   Length of the vectors.
    *   Control register to start operation and enable interrupts.
    *   Status register for busy/done/error.
    *   Result register to read the computed dot product.
*   **Operation:**
    1.  CPU configures the DSP and issues a start command.
    2.  DSP fetches elements from Vector A and Vector B from `DATA_MEM`.
    3.  Performs element-wise multiplication and accumulation.
    4.  Stores the final sum in its result register.
    5.  Notifies CPU of completion.

## 4. Getting Started

### 4.1. Prerequisites

*   **Verilator:** For Verilog simulation (version 4.210 or later recommended).
*   **Icarus Verilog:** (Optional, for alternative simulation/linting).
*   **Yosys:** For Verilog synthesis (optional, if targeting open-source flow).
*   **Xilinx Vivado:** For FPGA synthesis, implementation, and bitstream generation (version 2020.1 or later recommended). (Or any other FPGA vendor toolchain).
*   **RISC-V GCC Toolchain:** For compiling C/C++ programs for the RISC-V core (e.g., `riscv-none-embed-gcc` or `riscv64-unknown-elf-gcc` configured for RV32I).
*   **CMake:** For building the Verilator simulation.
*   **Make:** For running Makefile targets (FPGA build, Verilator via CMake).
*   **Docker:** (Recommended) For a consistent development and simulation environment. See `Dockerfile`.

### 4.2. Directory Structure
```
.
├── Processor/              # Core RISC-V processor and bus components
│   ├── PROCESSOR.v
│   ├── IFU.v
│   ├── INST_MEM.v
│   ├── CONTROL.v
│   ├── DATAPATH.v
│   ├── REG_FILE.v
│   ├── ALU.v
│   ├── DATA_MEM.v
│   ├── BUS_INTERCONNECT.v
│   ├── Processor_Mem_tb.v    # Testbench for basic memory ops
│   └── Processor_CDSP_tb.v   # Testbench for C program execution
├── DSP_CONV1D.v            # 1D Convolution DSP Accelerator
├── DSP_DOT_PRODUCT.v       # Dot Product DSP Accelerator
├── RISCV_DSP_SoC_Top.v     # Top-level module for FPGA synthesis
├── sim_main.cpp            # C++ test harness for Verilator
├── CMakeLists.txt          # CMake build script for Verilator
├── Makefile                # Makefile for FPGA flow and Verilator shortcuts
├── constraints.xdc         # Example XDC file for FPGA constraints
├── Dockerfile              # Docker configuration for environment setup
├── Research_Summary.md     # This document
└── LICENSE                 # Project License (MIT)
```

### 4.3. Setup and Simulation (Using Docker - Recommended)

1.  **Build Docker Image:**
    ```bash
    docker build -t riscv_dsp_env .
    ```
2.  **Run Docker Container:**
    ```bash
    docker run -it --rm -v $(pwd):/project riscv_dsp_env
    ```
    This mounts the current project directory into `/project` in the container.

3.  **Inside Docker Container: Build and Run Verilator Simulation:**
    *   Navigate to the Verilator build directory (created by CMake):
        ```bash
        mkdir -p build_verilator && cd build_verilator
        ```
    *   Run CMake to configure:
        ```bash
        cmake ..
        ```
    *   Compile the Verilated model and C++ harness:
        ```bash
        make
        # or specifically: make verilate_model
        ```
    *   Run the simulation (which uses `Processor_CDSP_tb.v` by default):
        ```bash
        make run_simulation
        # This will execute ./verilator_build/VProcessor_CDSP_tb
        ```
    *   A VCD trace file (`Processor_CDSP_tb_trace.vcd`) will be generated in the build directory (or wherever `run_simulation` target specifies). View with Gtkwave or similar.

### 4.4. FPGA Synthesis and Implementation (Using Makefile and Vivado)

1.  **Ensure Vivado is in your PATH** (or modify `VIVADO_CMD` in `Makefile`).
2.  **Create/Update `constraints.xdc`** with appropriate pin assignments and timing constraints for your target FPGA board.
3.  **Run Synthesis:**
    ```bash
    make synth
    ```
4.  **Run Implementation:**
    ```bash
    make impl
    ```
5.  **Generate Bitstream:**
    ```bash
    make bitstream
    ```
6.  **Program FPGA (Placeholder):**
    ```bash
    make program
    # (You'll need to customize the actual programming command in the Makefile)
    ```
7.  **Clean Build Files:**
    ```bash
    make clean
    ```

## 5. Running Tests

*   **Verilog Testbenches:**
    *   `Processor_Mem_tb.v`: A basic testbench for initial LW/SW instruction verification. (Can be adapted to be run with Verilator if a C++ harness is written for it, or simulated with Icarus Verilog).
    *   `Processor_CDSP_tb.v`: The primary testbench used with Verilator and `sim_main.cpp`. It is designed to:
        1.  Load a (conceptual) compiled C program into `INST_MEM.v` (currently, `INST_MEM.v` is filled with NOPs and has a placeholder for program inclusion).
        2.  Run the simulation for a set duration.
        3.  Check a specific memory location in `DATA_MEM` (e.g., `DATA_MEM[255]`) for a pass/fail signature written by the C program.
*   **C Program Tests (Conceptual):**
    *   The `Processor_CDSP_tb.v` is set up to verify a C program that would run on the RISC-V core, configure one or both DSPs, wait for completion, and write a success/failure signature to `DATA_MEM`.
    *   To run an actual C program:
        1.  Compile the C program using a RISC-V GCC toolchain (e.g., `riscv32-unknown-elf-gcc`).
        2.  Convert the compiled ELF/binary to a Verilog hex or procedural assignment format suitable for initializing `INST_MEM.v`. (Tools like `objcopy` and scripts can automate this).
        3.  Update `Processor/INST_MEM.v` to include this program data, replacing the default NOPs.
        4.  Re-run the Verilator simulation (`make run_simulation`).

## 6. Contributing

Contributions are welcome! Please feel free to fork the repository, make changes, and submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

Ensure that any Verilog contributions adhere to a consistent coding style and that simulations pass.

## 7. License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 8. Acknowledgements (Optional)

*   Thanks to the open-source community for tools like Verilator, Yosys, and RISC-V.
*   (Any other inspirations or acknowledgements).
