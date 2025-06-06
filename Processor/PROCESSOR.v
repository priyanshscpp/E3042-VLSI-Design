`include "CONTROL.v"
`include "DATAPATH.v"
`include "IFU.v"
// `include "DATA_MEM.v"` // DATA_MEM is still used, but BUS_INTERCONNECT will also be included
`include "DATA_MEM.v"
`include "BUS_INTERCONNECT.v"
`include "../DSP_CONV1D.v" // Assuming DSP_CONV1D.v is in the parent directory (root)

module PROCESSOR( 
    input clock, 
    input reset,
    output zero
);

    wire [31:0] instruction_code;
    wire [3:0] alu_control_w; // Renamed for clarity, as alu_control is also a port name in CONTROL
    wire regwrite_w;          // Renamed for clarity

    // New control signals from CONTROL module
    wire alu_src_b_w;
    wire mem_read_enable_w; // Output from CONTROL
    wire mem_write_enable_w; // Output from CONTROL
    wire mem_to_reg_w;       // Output from CONTROL
    wire stall_pipeline_w;   // Output from CONTROL to IFU

    // Immediate value
    wire [31:0] sign_extended_immediate_w;

    // Memory interface wires (CPU side - from DATAPATH to BUS_INTERCONNECT)
    wire [31:0] mem_addr_w;    // From DATAPATH: address from ALU for LW/SW
    wire [31:0] mem_wdata_w;   // From DATAPATH: data to be stored (rs2)
    wire [31:0] mem_rdata_w;   // To DATAPATH: data read from memory/peripheral via bus
    wire cpu_mem_ack_w;        // To DATAPATH (eventually): ack from bus for CPU requests

    // Wires for BUS_INTERCONNECT to DATA_MEM connection
    wire [7:0] bus_to_dm_addr_w;   // ADDR_WIDTH for DATA_MEM is 8
    wire [31:0] bus_to_dm_wdata_w;
    wire bus_to_dm_we_w;
    wire [31:0] dm_to_bus_rdata_w;

    // Wires for BUS_INTERCONNECT to DSP_CONV1D (AXI-Lite Slave IF)
    wire [4:0] bus_to_dsp_s_axi_awaddr_w; // DSP_REG_ADDR_WIDTH for DSP is 5
    wire bus_to_dsp_s_axi_awvalid_w;
    wire dsp_to_bus_s_axi_awready_w;
    wire [31:0] bus_to_dsp_s_axi_wdata_w;
    wire [3:0] bus_to_dsp_s_axi_wstrb_w; // 32-bit data -> 4-bit wstrb
    wire bus_to_dsp_s_axi_wvalid_w;
    wire dsp_to_bus_s_axi_wready_w;
    wire dsp_to_bus_s_axi_bvalid_w;
    wire bus_to_dsp_s_axi_bready_w;
    wire [1:0] dsp_to_bus_s_axi_bresp_w;

    wire [4:0] bus_to_dsp_s_axi_araddr_w;
    wire bus_to_dsp_s_axi_arvalid_w;
    wire dsp_to_bus_s_axi_arready_w;
    wire [31:0] dsp_to_bus_s_axi_rdata_w;
    wire [1:0] dsp_to_bus_s_axi_rresp_w;
    wire dsp_to_bus_s_axi_rvalid_w;
    wire bus_to_dsp_s_axi_rready_w;

    // Wires for DSP_CONV1D (Memory Master IF) to BUS_INTERCONNECT
    wire [31:0] dsp_master_to_bus_mem_addr_w;
    wire [31:0] bus_to_dsp_master_mem_rdata_w;
    wire dsp_master_to_bus_mem_req_w;
    wire bus_to_dsp_master_mem_ack_w;
    wire dsp_master_to_bus_mem_we_w;
    wire [31:0] dsp_master_to_bus_mem_wdata_w;

    // assign mem_rdata_w = 32'b0; // This was removed when DATA_MEM was directly connected.
                                 // mem_rdata_w is now an output from BUS_INTERCONNECT.

    IFU IFU_module(
        .clock(clock),
        .reset(reset),
        .stall_pipeline_i(stall_pipeline_w), // Stall signal from CONTROL
        .Instruction_Code(instruction_code)
    );
	
    CONTROL control_module(
        .funct7(instruction_code[31:25]),
        .funct3(instruction_code[14:12]),
        .opcode(instruction_code[6:0]),
        .alu_control(alu_control_w),
        .regwrite_control(regwrite_w),
        .mem_read_o(mem_read_enable_w),
        .mem_write_o(mem_write_enable_w),
        .mem_to_reg_o(mem_to_reg_w),
        .alu_src_b_o(alu_src_b_w),
        .mem_ack_i(cpu_mem_ack_w),         // Memory ack from BUS
        .stall_pipeline_o(stall_pipeline_w) // Stall signal to IFU
    );

    // Immediate generation logic
    // Opcode for LW (I-type): 7'b0000011
    // Opcode for SW (S-type): 7'b0100011
    assign sign_extended_immediate_w =
        (instruction_code[6:0] == 7'b0000011) ? {{20{instruction_code[31]}}, instruction_code[31:20]} : // I-type (LW)
        (instruction_code[6:0] == 7'b0100011) ? {{20{instruction_code[31]}}, instruction_code[31:25], instruction_code[11:7]} : // S-type (SW)
        32'b0; // Default for other types (e.g., R-type where immediate is not used by ALU directly via this path)
	
    DATAPATH datapath_module(
        // Existing ports from DATAPATH.v
        .read_reg_num1(instruction_code[19:15]),
        .read_reg_num2(instruction_code[24:20]),
        .write_reg(instruction_code[11:7]),
        .alu_control(alu_control_w),
        .regwrite(regwrite_w),
        .clock(clock),
        .reset(reset),
        .zero_flag(zero),
        // New connections (anticipating DATAPATH.v update)
        .immediate_value_i(sign_extended_immediate_w),
        .alu_src_b_i(alu_src_b_w),
        .mem_read_i(mem_read_enable_w),
        .mem_write_i(mem_write_enable_w),
        .mem_to_reg_i(mem_to_reg_w),
        .mem_rdata_i(mem_rdata_w),   // This is an input to DATAPATH
        .mem_addr_o(mem_addr_w),    // Output from DATAPATH (ALU result)
        .mem_wdata_o(mem_wdata_w),  // Output from DATAPATH (rs2 value)
        // .mem_rdata_i(mem_rdata_w)   // Duplicate .mem_rdata_i removed, already listed above.
        .mem_ack_i(cpu_mem_ack_w)   // Memory ack from BUS
    );

    BUS_INTERCONNECT bus_interconnect_module (
        // CPU Master Interface (from DATAPATH/CONTROL)
        .clk_i(clock),
        .reset_ni(~reset), // BUS_INTERCONNECT uses active low reset
        .cpu_mem_addr_i(mem_addr_w),
        .cpu_mem_wdata_i(mem_wdata_w),
        .cpu_mem_we_i(mem_write_enable_w), // From CONTROL
        .cpu_mem_re_i(mem_read_enable_w),  // From CONTROL
        .cpu_mem_rdata_o(mem_rdata_w),     // To DATAPATH
        .cpu_mem_ack_o(cpu_mem_ack_w),     // To DATAPATH (eventually)

        // DATA_MEM Slave Interface
        .dm_addr_o(bus_to_dm_addr_w),
        .dm_wdata_o(bus_to_dm_wdata_w),
        .dm_we_o(bus_to_dm_we_w),
        .dm_rdata_i(dm_to_bus_rdata_w),

        // DSP Registers AXI-Lite Slave Interface (to DSP_CONV1D)
        .dsp_s_axi_awaddr_o(bus_to_dsp_s_axi_awaddr_w),
        .dsp_s_axi_awvalid_o(bus_to_dsp_s_axi_awvalid_w),
        .dsp_s_axi_awready_i(dsp_to_bus_s_axi_awready_w),
        .dsp_s_axi_wdata_o(bus_to_dsp_s_axi_wdata_w),
        .dsp_s_axi_wstrb_o(bus_to_dsp_s_axi_wstrb_w),
        .dsp_s_axi_wvalid_o(bus_to_dsp_s_axi_wvalid_w),
        .dsp_s_axi_wready_i(dsp_to_bus_s_axi_wready_w),
        .dsp_s_axi_bvalid_i(dsp_to_bus_s_axi_bvalid_w),
        .dsp_s_axi_bready_o(bus_to_dsp_s_axi_bready_w),
        .dsp_s_axi_bresp_i(dsp_to_bus_s_axi_bresp_w),
        .dsp_s_axi_araddr_o(bus_to_dsp_s_axi_araddr_w),
        .dsp_s_axi_arvalid_o(bus_to_dsp_s_axi_arvalid_w),
        .dsp_s_axi_arready_i(dsp_to_bus_s_axi_arready_w),
        .dsp_s_axi_rdata_i(dsp_to_bus_s_axi_rdata_w),
        .dsp_s_axi_rresp_i(dsp_to_bus_s_axi_rresp_w),
        .dsp_s_axi_rvalid_i(dsp_to_bus_s_axi_rvalid_w),
        .dsp_s_axi_rready_o(bus_to_dsp_s_axi_rready_w),

        // DSP Memory Master Interface (from DSP_CONV1D)
        .dsp_mem_addr_i(dsp_master_to_bus_mem_addr_w),
        .dsp_mem_rdata_o(bus_to_dsp_master_mem_rdata_w),
        .dsp_mem_req_i(dsp_master_to_bus_mem_req_w),
        .dsp_mem_ack_o(bus_to_dsp_master_mem_ack_w),
        .dsp_mem_we_i(dsp_master_to_bus_mem_we_w),
        .dsp_mem_wdata_i(dsp_master_to_bus_mem_wdata_w)
    );

    DATA_MEM #(
        .ADDR_WIDTH(8) // Consistent with BUS_INTERCONNECT expectations
    ) data_memory_module (
        .clock(clock),
        .reset(reset), // DATA_MEM uses active high reset
        .addr_i(bus_to_dm_addr_w),
        .wdata_i(bus_to_dm_wdata_w),
        .we_i(bus_to_dm_we_w),
        .rdata_o(dm_to_bus_rdata_w)
    );

    DSP_CONV1D dsp_conv1d_module (
        // AXI-Lite Slave Interface (Connected to BUS_INTERCONNECT)
        .s_axi_clk(clock),
        .s_axi_resetn(~reset), // DSP AXI uses active low reset
        .s_axi_awaddr(bus_to_dsp_s_axi_awaddr_w),
        .s_axi_awvalid(bus_to_dsp_s_axi_awvalid_w),
        .s_axi_awready(dsp_to_bus_s_axi_awready_w),
        .s_axi_wdata(bus_to_dsp_s_axi_wdata_w),
        .s_axi_wstrb(bus_to_dsp_s_axi_wstrb_w),
        .s_axi_wvalid(bus_to_dsp_s_axi_wvalid_w),
        .s_axi_wready(dsp_to_bus_s_axi_wready_w),
        .s_axi_bvalid(dsp_to_bus_s_axi_bvalid_w),
        .s_axi_bready(bus_to_dsp_s_axi_bready_w),
        .s_axi_bresp(dsp_to_bus_s_axi_bresp_w),
        .s_axi_araddr(bus_to_dsp_s_axi_araddr_w),
        .s_axi_arvalid(bus_to_dsp_s_axi_arvalid_w),
        .s_axi_arready(dsp_to_bus_s_axi_arready_w),
        .s_axi_rdata(dsp_to_bus_s_axi_rdata_w),
        .s_axi_rresp(dsp_to_bus_s_axi_rresp_w),
        .s_axi_rvalid(dsp_to_bus_s_axi_rvalid_w),
        .s_axi_rready(bus_to_dsp_s_axi_rready_w),

        // DSP Control/Status
        .interrupt_o(/* connect to interrupt controller or leave open */),

        // DSP Memory Master Interface (Connected to BUS_INTERCONNECT)
        .dsp_mem_addr_o(dsp_master_to_bus_mem_addr_w),
        .dsp_mem_rdata_i(bus_to_dsp_master_mem_rdata_w),
        .dsp_mem_req_o(dsp_master_to_bus_mem_req_w),
        .dsp_mem_ack_i(bus_to_dsp_master_mem_ack_w),
        .dsp_mem_we_o(dsp_master_to_bus_mem_we_w),
        .dsp_mem_wdata_o(dsp_master_to_bus_mem_wdata_w)
    );

endmodule
