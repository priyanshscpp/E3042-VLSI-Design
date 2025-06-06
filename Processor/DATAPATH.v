`include "REG_FILE.v"
`include "ALU.v"

module DATAPATH(
    // Existing Ports
    input [4:0] read_reg_num1,
    input [4:0] read_reg_num2,
    input [4:0] write_reg,
    input [3:0] alu_control,
    input regwrite,
    input clock,
    input reset,
    output zero_flag,

    // New Inputs for immediate value and memory operations
    input [31:0] immediate_value_i,
    input alu_src_b_i,
    input mem_read_i,
    input mem_write_i,
    input mem_to_reg_i,
    input [31:0] mem_rdata_i,
    input mem_ack_i, // Memory acknowledgment from bus

    // New Outputs for memory interface
    output [31:0] mem_addr_o,
    output [31:0] mem_wdata_o,
    output mem_re_o,
    output mem_we_o
);

    // Internal wires
    wire [31:0] read_data1;
    wire [31:0] read_data2;
    wire [31:0] alu_operand_b;             // Selected second operand for ALU
    wire [31:0] alu_result_w;              // Output of the ALU
    wire [31:0] reg_write_data_mux_out_w;  // Output of the mux selecting data for register write
    wire effective_regwrite_w;             // Qualified register write signal

    // ALU Second Operand Mux
    // Selects between register data (rs2) or immediate value based on alu_src_b_i
    assign alu_operand_b = alu_src_b_i ? immediate_value_i : read_data2;

    // Instantiating the Register File
    // The write_data input is now sourced from reg_write_data_mux_out_w
    REG_FILE reg_file_module(
        .read_reg_num1(read_reg_num1),
        .read_reg_num2(read_reg_num2),
        .write_reg(write_reg),
        .write_data(reg_write_data_mux_out_w), // Changed from old 'write_data'
        .read_data1(read_data1),
        .read_data2(read_data2),
        .regwrite(effective_regwrite_w), // Use qualified regwrite
        .clock(clock),
        .reset(reset)
    );

    // Logic for effective_regwrite_w:
    // If regwrite is asserted by CONTROL:
    //   If mem_to_reg_i is true (it's an LW), then effective_regwrite_w is true only if mem_ack_i is also true.
    //   If mem_to_reg_i is false (it's an R-type or other), then effective_regwrite_w is true (passes regwrite through).
    assign effective_regwrite_w = regwrite && (mem_to_reg_i ? mem_ack_i : 1'b1);

    // Instantiating ALU
    // Second operand is now alu_operand_b, result goes to alu_result_w
    ALU alu_module(
        .in1(read_data1),
        .in2(alu_operand_b),
        .alu_control(alu_control),
        .alu_result(alu_result_w),
        .zero_flag(zero_flag)
    );
	 
    // Memory Address Output
    // ALU result is used as the memory address for LW/SW
    assign mem_addr_o = alu_result_w;

    // Memory Write Data Output
    // For SW, read_data2 (from rs2) is the data to be written to memory
    assign mem_wdata_o = read_data2;

    // Register Write Data Mux
    // Selects between data from memory (LW) or ALU result for register write back
    assign reg_write_data_mux_out_w = mem_to_reg_i ? mem_rdata_i : alu_result_w;

    // Memory Read/Write Enable Outputs
    // Pass through control signals from the CONTROL module
    assign mem_re_o = mem_read_i;
    assign mem_we_o = mem_write_i;

endmodule
