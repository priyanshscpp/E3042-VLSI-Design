# Makefile for RISC-V SoC with DSP Accelerators - FPGA Build (Xilinx Vivado)

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
# Project Configuration
PROJECT_NAME      := RISCV_DSP_SoC_Top
FPGA_PART         := xc7a35tcpg236-1 # Example Artix-7 part, replace with your target
TOP_MODULE        := $(PROJECT_NAME)

# Source Files - Assuming Makefile is in the project root
# Add all necessary Verilog files. Paths should be relative to this Makefile.
VERILOG_SOURCES   := \
    ./RISCV_DSP_SoC_Top.v \
    ./DSP_CONV1D.v \
    ./DSP_DOT_PRODUCT.v \
    ./Processor/PROCESSOR.v \
    ./Processor/IFU.v \
    ./Processor/INST_MEM.v \
    ./Processor/CONTROL.v \
    ./Processor/DATAPATH.v \
    ./Processor/REG_FILE.v \
    ./Processor/ALU.v \
    ./Processor/DATA_MEM.v \
    ./Processor/BUS_INTERCONNECT.v

# Constraints File
XDC_FILE          := ./constraints.xdc # Assumed to be in the root, create this file

# Tools
VIVADO_CMD        := vivado # Or full path to Vivado executable

# Build Directories
BUILD_DIR         := ./build_fpga
REPORTS_DIR       := $(BUILD_DIR)/reports
SYNTH_DIR         := $(BUILD_DIR)/synth
IMPL_DIR          := $(BUILD_DIR)/impl
BITSTREAM_DIR     := $(BUILD_DIR)/bitstream

# Generated Files
SYNTH_DCP         := $(SYNTH_DIR)/$(PROJECT_NAME)_synth.dcp
IMPL_DCP          := $(IMPL_DIR)/$(PROJECT_NAME)_impl.dcp
BITSTREAM_FILE    := $(BITSTREAM_DIR)/$(PROJECT_NAME).bit
PROBES_FILE       := $(BITSTREAM_DIR)/$(PROJECT_NAME).ltx

# TCL Scripts (will be generated)
SYNTH_TCL         := $(SYNTH_DIR)/synth.tcl
IMPL_TCL          := $(IMPL_DIR)/impl.tcl
BITSTREAM_TCL     := $(BITSTREAM_DIR)/bitstream.tcl

# Shell for Makefile execution
SHELL := /bin/bash

# -----------------------------------------------------------------------------
# Standard Targets
# -----------------------------------------------------------------------------
.PHONY: all synth impl bitstream program clean help setup_dirs

all: bitstream

setup_dirs:
	@echo "Setting up build directories..."
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(REPORTS_DIR)
	@mkdir -p $(SYNTH_DIR)
	@mkdir -p $(IMPL_DIR)
	@mkdir -p $(BITSTREAM_DIR)

# -----------------------------------------------------------------------------
# Synthesis
# -----------------------------------------------------------------------------
define VIVADO_SYNTH_TCL_TEMPLATE
# Vivado Synthesis Script

# Set the target FPGA part
set_part $(FPGA_PART)

# Add Verilog source files
# Note: Vivado prefers absolute paths or paths relative to where the script is run,
# or paths relative to a project directory if a project is created.
# For non-project batch mode, ensure paths are correct.
# Using `read_verilog [glob <path_to_sources>]` can also be an option if sources are organized.
add_files -norecurse { \
    $(foreach src,$(VERILOG_SOURCES),$(abspath $(src)) \
)}

# Add constraints file
add_files -fileset constrs_1 -norecurse $(abspath $(XDC_FILE))

# Synthesis settings (example)
# synth_design -top $(TOP_MODULE) -part $(FPGA_PART) -mode out_of_context (for IP-like flow)
synth_design -top $(TOP_MODULE) -part $(FPGA_PART)

# Write checkpoint and reports
write_checkpoint -force $(abspath $(SYNTH_DCP))
report_timing_summary -file $(abspath $(REPORTS_DIR))/post_synth_timing_summary.rpt
report_utilization -file $(abspath $(REPORTS_DIR))/post_synth_utilization.rpt

puts "Synthesis complete. Checkpoint: $(abspath $(SYNTH_DCP))"
endef
export VIVADO_SYNTH_TCL_TEMPLATE

$(SYNTH_TCL):
	@echo "$$VIVADO_SYNTH_TCL_TEMPLATE" > $(SYNTH_TCL)

synth: setup_dirs $(SYNTH_TCL) $(VERILOG_SOURCES) $(XDC_FILE)
	@echo "Running Vivado Synthesis..."
	$(VIVADO_CMD) -mode batch -source $(SYNTH_TCL) -log $(SYNTH_DIR)/vivado_synth.log -journal $(SYNTH_DIR)/vivado_synth.jou
	@echo "Synthesis finished. Checkpoint: $(SYNTH_DCP)"


# -----------------------------------------------------------------------------
# Implementation
# -----------------------------------------------------------------------------
define VIVADO_IMPL_TCL_TEMPLATE
# Vivado Implementation Script

# Open Synthesized Design Checkpoint
open_checkpoint $(abspath $(SYNTH_DCP))

# Optimization (optional, Vivado runs some by default)
# opt_design
# report_drc -file $(abspath $(REPORTS_DIR))/opt_drc.rpt

# Placement
place_design
# report_io -file $(abspath $(REPORTS_DIR))/place_io.rpt
# report_utilization -file $(abspath $(REPORTS_DIR))/place_utilization.rpt
# report_control_sets -verbose -file $(abspath $(REPORTS_DIR))/place_control_sets.rpt

# Routing
route_design
# report_drc -file $(abspath $(REPORTS_DIR))/route_drc.rpt
# report_timing_summary -file $(abspath $(REPORTS_DIR))/post_route_timing_summary.rpt
# report_power -file $(abspath $(REPORTS_DIR))/post_route_power.rpt
# report_route_status -file $(abspath $(REPORTS_DIR))/post_route_status.rpt

# Write checkpoint
write_checkpoint -force $(abspath $(IMPL_DCP))

puts "Implementation complete. Checkpoint: $(abspath $(IMPL_DCP))"
endef
export VIVADO_IMPL_TCL_TEMPLATE

$(IMPL_TCL):
	@echo "$$VIVADO_IMPL_TCL_TEMPLATE" > $(IMPL_TCL)

impl: $(IMPL_TCL) $(SYNTH_DCP)
	@echo "Running Vivado Implementation..."
	$(VIVADO_CMD) -mode batch -source $(IMPL_TCL) -log $(IMPL_DIR)/vivado_impl.log -journal $(IMPL_DIR)/vivado_impl.jou
	@echo "Implementation finished. Checkpoint: $(IMPL_DCP)"


# -----------------------------------------------------------------------------
# Bitstream Generation
# -----------------------------------------------------------------------------
define VIVADO_BITSTREAM_TCL_TEMPLATE
# Vivado Bitstream Generation Script

# Open Implemented Design Checkpoint
open_checkpoint $(abspath $(IMPL_DCP))

# Bitstream settings (example)
# set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Write Bitstream
write_bitstream -force $(abspath $(BITSTREAM_FILE))

# Optional: Write LTX file for hardware debugger
# write_debug_probes -force $(abspath $(PROBES_FILE))

puts "Bitstream generation complete. File: $(abspath $(BITSTREAM_FILE))"
endef
export VIVADO_BITSTREAM_TCL_TEMPLATE

$(BITSTREAM_TCL):
	@echo "$$VIVADO_BITSTREAM_TCL_TEMPLATE" > $(BITSTREAM_TCL)

bitstream: $(BITSTREAM_TCL) $(IMPL_DCP)
	@echo "Generating Bitstream..."
	$(VIVADO_CMD) -mode batch -source $(BITSTREAM_TCL) -log $(BITSTREAM_DIR)/vivado_bitstream.log -journal $(BITSTREAM_DIR)/vivado_bitstream.jou
	@echo "Bitstream generated: $(BITSTREAM_FILE)"


# -----------------------------------------------------------------------------
# Program FPGA (Placeholder)
# -----------------------------------------------------------------------------
program: $(BITSTREAM_FILE)
	@echo "Programming FPGA with $(BITSTREAM_FILE)..."
	# Add your FPGA programming command here, e.g.:
	# $(VIVADO_CMD) -mode tcl -source path/to/your_program_script.tcl
	@echo "Note: 'program' target is a placeholder. Implement actual programming command."


# -----------------------------------------------------------------------------
# Utility Targets
# -----------------------------------------------------------------------------
clean:
	@echo "Cleaning build directories and generated files..."
	@rm -rf $(BUILD_DIR)
	@rm -f vivado*.log vivado*.jou vivado*.str hs_err_*.log # Remove Vivado general log/journal files
	@echo "Clean complete."

help:
	@echo "Available targets:"
	@echo "  all          - Build the entire project (default: generates bitstream)"
	@echo "  setup_dirs   - Create necessary build directories"
	@echo "  synth        - Run Vivado synthesis"
	@echo "  impl         - Run Vivado implementation (requires synthesis)"
	@echo "  bitstream    - Generate bitstream (requires implementation)"
	@echo "  program      - Placeholder for programming the FPGA (requires bitstream)"
	@echo "  clean        - Remove all generated build files and directories"
	@echo "  help         - Show this help message"

# Prevent .PHONY targets from interfering with files of the same name
.SECONDARY: $(SYNTH_TCL) $(IMPL_TCL) $(BITSTREAM_TCL)
