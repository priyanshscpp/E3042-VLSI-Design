// RISCV_DSP_SoC_Top.v
`timescale 1ns / 1ps

// It's assumed that all necessary Verilog files (`PROCESSOR.v` and its submodules,
// `BUS_INTERCONNECT.v`, `DATA_MEM.v`, `DSP_CONV1D.v`) are available to the synthesis tool
// either by being in the same directory or through search paths.
// For synthesis, specific `include directives within modules are generally preferred
// over including everything at the top level here, but PROCESSOR.v already includes its components.
// If needed for linters or specific tool flows, one might add:
// `include "Processor/PROCESSOR.v"

module RISCV_DSP_SoC_Top (
    input wire sys_clk_i,   // System clock input
    input wire sys_reset_i, // System reset input (active high for this top level)

    // Example output for status (e.g., to an LED)
    // output wire dsp_done_led_o, // Example, not implemented via DSP output yet
    output wire cpu_halted_led_o // Tied to a signal indicating C program end for visual cue
);

    // Internal signals
    wire proc_clock;
    wire proc_reset; // PROCESSOR module uses active high reset

    // Clock management (e.g., using a PLL/MMCM later, for now direct connection or buffer)
    // For simplicity, assume sys_clk_i can directly drive proc_clock
    assign proc_clock = sys_clk_i;

    // Reset synchronization (optional but good practice, for now direct)
    // Ensure proc_reset is synchronous to proc_clock if sys_reset_i is asynchronous
    // For this example, sys_reset_i is assumed to be synchronous or properly handled externally.
    assign proc_reset = sys_reset_i;


    // Instantiate the PROCESSOR system
    // Note: The PROCESSOR module itself includes:
    // IFU (with INST_MEM), CONTROL, DATAPATH (with REG_FILE),
    // BUS_INTERCONNECT, DATA_MEM, and DSP_CONV1D.
    PROCESSOR processor_inst (
        .clock(proc_clock),
        .reset(proc_reset),
        .zero() // zero flag from ALU, not used at top level currently
    );

    // Example: Drive an LED if the CPU writes a specific "halt" signature
    // This requires the C program to write to a specific, unused DATA_MEM location
    // that the testbench or this top module can monitor.
    // Let's say C program at end writes to DATA_MEM[254] = 0xDEADBEEF
    // This is a simplified way to show program completion on FPGA if no UART/debug.
    // IMPORTANT: Hierarchical access like this is primarily for simulation.
    // For synthesis, this signal would need to be explicitly output from PROCESSOR.v,
    // or use specific synthesis attributes if available (e.g., DONT_TOUCH on the path,
    // then tap it, though this is less portable/clean).
    // A cleaner method is a dedicated status register or output port from PROCESSOR.
    assign cpu_halted_led_o = (processor_inst.data_memory_module.memory_array[254] == 32'hDEADBEEF);

    // To drive dsp_done_led_o, you'd need to bring dsp_done signal to top:
    // Example (requires dsp_done_o port on PROCESSOR, connected to DSP's done_r):
    // wire dsp_module_done_w; // Assume this comes from an output of processor_inst
    // assign dsp_done_led_o = dsp_module_done_w;

endmodule
