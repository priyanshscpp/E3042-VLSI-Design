cmake_minimum_required(VERSION 3.10)
project(RISCV_DSP_SoC_Verilator_Sim CXX C)

# Find Verilator
find_program(VERILATOR_EXECUTABLE verilator)
if(NOT VERILATOR_EXECUTABLE)
    message(FATAL_ERROR "Verilator not found. Please install Verilator or ensure it's in your PATH.")
endif()
message(STATUS "Found Verilator: ${VERILATOR_EXECUTABLE}")

# Set Verilator options
set(VERILATOR_OPTIONS "")
list(APPEND VERILATOR_OPTIONS "--cc")                     # Create C++ output
list(APPEND VERILATOR_OPTIONS "--exe")                    # Create executable
list(APPEND VERILATOR_OPTIONS "-CFLAGS \"-std=c++11\"") # Use C++11 for the simulation harness
list(APPEND VERILATOR_OPTIONS "--build")                  # Build the model automatically
list(APPEND VERILATOR_OPTIONS "-j $(nproc)")              # Parallel build
list(APPEND VERILATOR_OPTIONS "--trace")                  # Enable VCD tracing
list(APPEND VERILATOR_OPTIONS "--assert")                 # Enable assertions
list(APPEND VERILATOR_OPTIONS "-Wall")                    # Verilog warnings
list(APPEND VERILATOR_OPTIONS "-Wno-fatal")               # Don't treat warnings as errors for now
list(APPEND VERILATOR_OPTIONS "-Wno-WIDTH")               # Suppress some common width warnings if needed
list(APPEND VERILATOR_OPTIONS "-Wno-STMTDLY")             # Suppress statement delay warnings
list(APPEND VERILATOR_OPTIONS "--timing")                 # Experimental: add timing support for more accurate sim

# Define the top Verilog module for Verilation (this should be the testbench)
set(VERILOG_TOP_MODULE "Processor_CDSP_tb")

# List all Verilog source files (including the testbench)
# Ensure paths are relative to this CMakeLists.txt file (project root)
set(VERILOG_SOURCES
    "DSP_CONV1D.v"
    "DSP_DOT_PRODUCT.v"
    "Processor/PROCESSOR.v"
    "Processor/IFU.v"
    "Processor/INST_MEM.v"
    "Processor/CONTROL.v"
    "Processor/DATAPATH.v"
    "Processor/REG_FILE.v"
    "Processor/ALU.v"
    "Processor/DATA_MEM.v"
    "Processor/BUS_INTERCONNECT.v"
    "Processor/Processor_CDSP_tb.v"
)

# List the C++ simulation driver file
set(SIM_DRIVER_CPP "sim_main.cpp")

# Output directory for Verilator generated files and build artifacts
set(VERILATOR_OUTPUT_DIR "${CMAKE_BINARY_DIR}/verilator_build")

# Add a custom command to run Verilator
# This command generates C++ code from Verilog and compiles it into an executable
add_custom_command(
    OUTPUT "${VERILATOR_OUTPUT_DIR}/V${VERILOG_TOP_MODULE}" # Expected executable
    COMMAND ${VERILATOR_EXECUTABLE}
            ${VERILATOR_OPTIONS}
            --top-module ${VERILOG_TOP_MODULE}
            -IProcessor                       # Include directory for `include "MODULE.v"
            ${VERILOG_SOURCES}
            --main ${SIM_DRIVER_CPP}          # Specify the C++ driver
            -o "${VERILATOR_OUTPUT_DIR}/V${VERILOG_TOP_MODULE}" # Output executable name
            --Mdir "${VERILATOR_OUTPUT_DIR}/obj_dir_V${VERILOG_TOP_MODULE}" # Output directory for generated files
    DEPENDS ${VERILOG_SOURCES} ${SIM_DRIVER_CPP}
    COMMENT "Verilating ${VERILOG_TOP_MODULE}..."
    VERBATIM
)

# Add a custom target that depends on the Verilator command's output
add_custom_target(verilate_model ALL
    DEPENDS "${VERILATOR_OUTPUT_DIR}/V${VERILOG_TOP_MODULE}"
)

# Add a custom target to run the simulation
add_custom_target(run_simulation
    COMMAND "${VERILATOR_OUTPUT_DIR}/V${VERILOG_TOP_MODULE}"
    DEPENDS verilate_model
    COMMENT "Running simulation..."
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR} # Or ${CMAKE_CURRENT_SOURCE_DIR}
)

# Optional: Add a clean target for Verilator build files
add_custom_target(clean_verilator
    COMMAND ${CMAKE_COMMAND} -E remove_directory "${VERILATOR_OUTPUT_DIR}"
    COMMENT "Cleaning Verilator build files..."
)

message(STATUS "CMake setup complete. To build the simulation: make verilate_model (or just make)")
message(STATUS "To run the simulation: make run_simulation")
message(STATUS "To clean Verilator files: make clean_verilator")
