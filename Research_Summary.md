# Research Summary: Enhancing RISC-V with a Lightweight 1D Convolution DSP Accelerator

## 1. Introduction

RISC-V, an open-source instruction set architecture (ISA), offers flexibility and scalability, making it a popular choice for a wide range of applications, from embedded systems to high-performance computing. However, for computationally intensive tasks prevalent in modern wireless communications (e.g., filtering, modulation) and edge Machine Learning (e.g., convolutional layers in neural networks), a general-purpose RISC-V core may not provide sufficient performance or energy efficiency. This project explores the benefits of integrating a lightweight, custom Digital Signal Processing (DSP) accelerator with a 32-bit RISC-V processor to offload specific computations, thereby enhancing overall system performance and potentially reducing power consumption.

We designed a 1D convolution accelerator, a fundamental operation in many DSP and ML algorithms. This accelerator was integrated into a RISC-V system featuring instruction and data memories, a register file, and a custom bus interconnect for communication between the CPU, data memory, and the DSP unit.

## 2. System Architecture

The integrated system comprises the following key components:

*   **RISC-V CPU:** A 32-bit processor (rv32i base) with support for load/store operations and a mechanism to handle multi-cycle memory/peripheral accesses (wait states).
*   **Instruction Memory (INST_MEM):** Stores the RISC-V program instructions.
*   **Data Memory (DATA_MEM):** Used for general data storage, accessible by both the CPU and the DSP accelerator.
*   **DSP_CONV1D Accelerator:** A custom hardware block designed to perform 1D convolution.
    *   **AXI-Lite Slave Interface:** Allows the CPU to configure the DSP (set data/kernel addresses, lengths) and control its operation (start, interrupt enable, read status).
    *   **Memory Master Interface (Placeholder):** Enables the DSP to autonomously fetch input data and filter kernels from `DATA_MEM` and write results back.
    *   **Internal Logic:** Includes a Finite State Machine (FSM) to manage the convolution steps (fetch, MAC, store) and a Multiply-Accumulate (MAC) datapath.
*   **Bus Interconnect:** A central module that:
    *   Decodes memory addresses from the CPU.
    *   Routes CPU requests to either `DATA_MEM` or the DSP's AXI-Lite registers.
    *   Arbitrates access to `DATA_MEM` between the CPU and the DSP (CPU priority).
*   **DSP_DOT_PRODUCT Accelerator:** A second custom hardware block designed to perform vector dot product operations, also featuring an AXI-Lite slave interface and memory master capabilities.

**(A block diagram similar to the textual one provided previously would be inserted here)**

## 3. DSP Accelerator Designs

### 3.1 1D Convolution Unit

The 1D convolution unit performs the operation: `Output[i] = sum(Input[i+j] * Kernel[j]) for j = 0 to KernelLength-1`.

*   **Configurability:** The DSP is configured via memory-mapped registers, allowing the CPU to specify:
    *   Base addresses for input data, kernel, and output data buffers in `DATA_MEM`.
    *   Lengths of the input data array and the kernel.
*   **Operation Flow:**
    1.  CPU writes configuration parameters and the 'start' command to the DSP.
    2.  The DSP's FSM takes over:
        *   Initializes its internal accumulator and pointers.
        *   Iteratively fetches one kernel value and one corresponding input data value from `DATA_MEM`.
        *   Performs a multiply-accumulate operation.
        *   Repeats until all kernel taps are processed for one output element.
        *   Stores the computed output element back to `DATA_MEM`.
        *   Repeats for all output elements.
    3.  Sets a 'done' flag in its status register and can optionally raise an interrupt.
    4.  The CPU polls the status register (or services the interrupt) to know when the operation is complete and results are ready.

**(A diagram of the DSP internal datapath/FSM interaction would be inserted here)**

### 3.2 Dot Product Unit

In addition to the 1D convolution unit, a Dot Product accelerator was also integrated. This unit computes the sum of the element-wise products of two vectors: `Result = sum(VectorA[j] * VectorB[j])`.
*   **Configuration:** Similar to the convolution DSP, it's configured via AXI-Lite registers for vector base addresses (in `DATA_MEM`) and vector length.
*   **Result Retrieval:** The final dot product sum is made available in a dedicated AXI-readable result register within the Dot Product DSP.
*   **Operation:** It fetches elements from both input vectors from `DATA_MEM`, performs the multiply-accumulate operations internally, and signals completion via its status register.

## 4. Anticipated Performance Benefits & Benchmarks

Integrating a hardware accelerator for convolution is expected to yield significant performance improvements over a purely software-based implementation on the RISC-V core.

**(The conceptual benchmark table would be inserted here, ideally populated with expected or hypothetical values if actual results are pending)**

*   **Cycle Count Reduction:** Hardware acceleration performs MAC operations in parallel or in a highly optimized pipeline, drastically reducing the number of clock cycles compared to sequential software loops involving loads, multiplies, adds, and stores for each step of the convolution. We anticipate `[Cycles_DSP]` to be significantly lower than `[Cycles_SW]`.
*   **Increased Throughput:** Lower cycle counts directly translate to higher throughput for convolution tasks. This is critical for real-time signal processing in wireless systems (e.g., FIR/IIR filtering) and faster inference in ML applications (e.g., processing layers of a CNN).
*   **CPU Offloading:** While the DSP is active, the RISC-V CPU is free to perform other tasks (e.g., protocol stack management in wireless, decision making in ML), improving overall system responsiveness. If no other tasks are available, the CPU can enter a low-power state, waiting for a DSP completion interrupt.
*   **Energy Efficiency:** Custom hardware is generally more power-efficient for specific tasks than general-purpose CPUs executing software. By offloading the MAC-intensive convolution, the overall energy per operation is expected to decrease, which is vital for battery-powered edge devices.

## 5. Relevance to Wireless/ML Applications

*   **Wireless Communications:**
    *   **Channel Filtering (FIR/IIR):** 1D convolution is the core of FIR filters, widely used for channel selection, noise reduction, and pulse shaping. Hardware acceleration ensures these filters can operate at high data rates.
    *   **Synchronization:** Correlation, a key step in synchronization, is mathematically similar to convolution.
    *   **Equalization:** Adaptive filters often use convolution-like operations.
*   **Machine Learning (Edge AI/TinyML):**
    *   **Convolutional Neural Networks (CNNs):** 1D CNNs are used for time-series data, sensor data analysis, and simpler image/pattern recognition tasks. The convolution accelerator can significantly speed up the execution of these layers.
    *   **Feature Extraction:** Convolution can be used for extracting features from sensor streams before feeding them to a simpler classifier.
    *   **Keyword Spotting & Simple Speech Processing:** Often involve 1D convolutions on audio data.
*   **Vector Operations (Dot Products):** Dot products are fundamental in many ML algorithms, including calculating neuron outputs (weighted sums), similarity measures, and projections. Accelerating this can significantly benefit various ML models. They also appear in wireless applications for correlation and matched filtering.

The ability to perform these operations quickly and efficiently on a low-power RISC-V platform augmented with DSP capabilities makes such a system highly suitable for intelligent edge devices.

## 6. Conclusion and Future Work

The integration of a lightweight 1D convolution DSP accelerator demonstrates a promising path to enhancing the performance and efficiency of RISC-V based SoCs for specialized workloads in wireless communications and machine learning. The designed system, with its 1D convolution and dot product accelerators, allows the CPU to offload compute-intensive tasks, freeing it for other operations and potentially reducing overall power consumption.

Future work could involve:
*   Implementing and verifying the system on an FPGA to obtain actual benchmark numbers for performance, area, and power.
*   Adding more sophisticated bus features (e.g., DMA for data transfers to/from DSP).
*   Expanding the DSP with more kernels (e.g., FFT, full matrix multiplication for larger ML models) beyond the currently implemented convolution and dot product units.
*   Implementing interrupt handling in the RISC-V CPU for more efficient DSP completion signaling.
*   Developing a more comprehensive software stack, including drivers for the DSP.

This project serves as a foundational step, showcasing the potential of custom hardware acceleration within the flexible RISC-V ecosystem.
