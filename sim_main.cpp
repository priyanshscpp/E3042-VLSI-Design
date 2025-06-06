#include "verilated.h"
#include "verilated_vcd_c.h"
#include "VProcessor_CDSP_tb.h" // Include the Verilator-generated header for the testbench

#include <iostream>
#include <cstdint> // For uint64_t

// Required for Verilator
// Keeps track of simulation time
static uint64_t main_time = 0;
double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv, char** env) {
    // Initialize Verilator
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true); // Enable VCD tracing

    // Instantiate the Verilated module (our testbench)
    VProcessor_CDSP_tb* top = new VProcessor_CDSP_tb;

    // Initialize VCD trace
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99); // Trace 99 levels of hierarchy
    tfp->open("Processor_CDSP_tb_trace.vcd"); // Open the VCD file for writing

    std::cout << "Starting Verilator simulation..." << std::endl;

    // Simulation loop
    const uint64_t SIMULATION_TIMEOUT_CYCLES = 100000; // Approx 1ms at 100MHz (10ns per cycle)
                                                       // Needs to be longer than #60000ns in testbench
    uint64_t cycle_count = 0;

    // Initial reset (as done in Verilog testbench's initial block)
    // The Verilog testbench itself handles reset signal toggling.
    // We just need to advance time.

    while (!Verilated::gotFinish() && cycle_count < SIMULATION_TIMEOUT_CYCLES) {
        // Toggle clock
        top->clock = 0;
        top->eval();
        tfp->dump(main_time);
        main_time += 5; // Half clock cycle (5ns for 100MHz)

        top->clock = 1;
        top->eval();
        tfp->dump(main_time);
        main_time += 5; // Other half clock cycle

        cycle_count++;

        // Optional: Print status every N cycles
        // if (cycle_count % 1000 == 0) {
        //     std::cout << "Cycle: " << cycle_count << std::endl;
        // }
    }

    if (cycle_count >= SIMULATION_TIMEOUT_CYCLES && !Verilated::gotFinish()) {
        std::cout << "ERROR: Simulation TIMEOUT after " << cycle_count << " cycles!" << std::endl;
        std::cout << "The Verilog testbench did not call $finish." << std::endl;
    } else {
        std::cout << "Simulation finished in " << cycle_count << " Verilator cycles." << std::endl;
    }
    std::cout << "Final simulation time: " << main_time << " (time units, e.g., ps if timescale 1ps)" << std::endl;


    // Clean up
    if (tfp) {
        tfp->close();
        delete tfp;
    }
    delete top;

    return 0;
}
