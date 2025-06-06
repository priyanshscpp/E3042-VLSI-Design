module BUS_INTERCONNECT #(
    parameter CPU_DATA_WIDTH = 32,
    parameter CPU_ADDR_WIDTH = 32,
    parameter MEM_ADDR_WIDTH = 8, // For DATA_MEM, e.g., 2^8 = 256 words
    parameter DSP_REG_ADDR_WIDTH = 5, // For DSP AXI-Lite, e.g., 2^5 = 32 bytes
    parameter DSP_MEM_DATA_WIDTH = 32,

    localparam NUM_DATA_MEM_WORDS = 1 << MEM_ADDR_WIDTH,
    localparam DATA_MEM_SIZE_BYTES = NUM_DATA_MEM_WORDS * (CPU_DATA_WIDTH/8),
    parameter DATA_MEM_BASE_ADDR = 32'h00000000,
    parameter DATA_MEM_END_ADDR = DATA_MEM_BASE_ADDR + DATA_MEM_SIZE_BYTES - 1, // e.g., 0x000_03FF for 256 words

    localparam DSP_REG_SPACE_BYTES = 1 << DSP_REG_ADDR_WIDTH,
    parameter DSP_REG_BASE_ADDR = 32'h80000000,
    parameter DSP_REG_END_ADDR = DSP_REG_BASE_ADDR + DSP_REG_SPACE_BYTES - 1 // e.g., 0x8000_001F for 32 bytes
)(
    // CPU Master Interface (from DATAPATH)
    input clk_i,
    input reset_ni, // Active low reset

    input [CPU_ADDR_WIDTH-1:0] cpu_mem_addr_i,
    input [CPU_DATA_WIDTH-1:0] cpu_mem_wdata_i,
    input cpu_mem_we_i,  // Write enable from CPU
    input cpu_mem_re_i,  // Read enable from CPU (can be ORed with we_i for general request)
    output reg [CPU_DATA_WIDTH-1:0] cpu_mem_rdata_o,
    output reg cpu_mem_ack_o,

    // DATA_MEM Slave Interface
    output reg [MEM_ADDR_WIDTH-1:0] dm_addr_o,
    output reg [CPU_DATA_WIDTH-1:0] dm_wdata_o,
    output reg dm_we_o,
    input [CPU_DATA_WIDTH-1:0] dm_rdata_i,

    // DSP Registers AXI-Lite Slave Interface (to DSP_CONV1D)
    output reg [DSP_REG_ADDR_WIDTH-1:0] dsp_s_axi_awaddr_o,
    output reg dsp_s_axi_awvalid_o,
    input dsp_s_axi_awready_i,
    output reg [CPU_DATA_WIDTH-1:0] dsp_s_axi_wdata_o,
    output reg [CPU_DATA_WIDTH/8-1:0] dsp_s_axi_wstrb_o,
    output reg dsp_s_axi_wvalid_o,
    input dsp_s_axi_wready_i,
    input dsp_s_axi_bvalid_i,
    output reg dsp_s_axi_bready_o,
    input [1:0] dsp_s_axi_bresp_i,

    output reg [DSP_REG_ADDR_WIDTH-1:0] dsp_s_axi_araddr_o,
    output reg dsp_s_axi_arvalid_o,
    input dsp_s_axi_arready_i,
    input [CPU_DATA_WIDTH-1:0] dsp_s_axi_rdata_i,
    input [1:0] dsp_s_axi_rresp_i,
    input dsp_s_axi_rvalid_i,
    output reg dsp_s_axi_rready_o,

    // DSP Memory Master Interface (from DSP_CONV1D, to access DATA_MEM)
    input [CPU_ADDR_WIDTH-1:0] dsp_mem_addr_i, // DSP provides full byte address
    output reg [DSP_MEM_DATA_WIDTH-1:0] dsp_mem_rdata_o,
    input dsp_mem_req_i,
    output reg dsp_mem_ack_o,
    input dsp_mem_we_i, // Write enable from DSP
    input [DSP_MEM_DATA_WIDTH-1:0] dsp_mem_wdata_i
);

    // Address Decoding
    wire cpu_req_active_w = cpu_mem_re_i || cpu_mem_we_i;
    wire cpu_access_data_mem_w = cpu_req_active_w &&
                                (cpu_mem_addr_i >= DATA_MEM_BASE_ADDR) &&
                                (cpu_mem_addr_i <= DATA_MEM_END_ADDR);

    wire cpu_access_dsp_regs_w = cpu_req_active_w &&
                                (cpu_mem_addr_i >= DSP_REG_BASE_ADDR) &&
                                (cpu_mem_addr_i <= DSP_REG_END_ADDR);

    // DSP Access to Data Memory (DSP provides byte address)
    wire dsp_access_data_mem_w = dsp_mem_req_i &&
                               (dsp_mem_addr_i >= DATA_MEM_BASE_ADDR) &&
                               (dsp_mem_addr_i <= DATA_MEM_END_ADDR);

    // Arbitration: CPU has priority for DATA_MEM access
    wire cpu_granted_data_mem_w = cpu_access_data_mem_w;
    wire dsp_granted_data_mem_w = dsp_access_data_mem_w && !cpu_granted_data_mem_w;


    // Combinational logic for routing and acknowledgements
    always @(*) begin
        // Default assignments
        cpu_mem_rdata_o = {CPU_DATA_WIDTH{1'b0}};
        cpu_mem_ack_o   = 1'b0;

        dm_addr_o       = {MEM_ADDR_WIDTH{1'b0}};
        dm_wdata_o      = {CPU_DATA_WIDTH{1'b0}};
        dm_we_o         = 1'b0;

        dsp_s_axi_awaddr_o = {DSP_REG_ADDR_WIDTH{1'b0}};
        dsp_s_axi_awvalid_o= 1'b0;
        dsp_s_axi_wdata_o  = {CPU_DATA_WIDTH{1'b0}};
        dsp_s_axi_wstrb_o  = {(CPU_DATA_WIDTH/8){1'b0}};
        dsp_s_axi_wvalid_o = 1'b0;
        dsp_s_axi_bready_o = 1'b0; // Default: not ready to accept bvalid

        dsp_s_axi_araddr_o = {DSP_REG_ADDR_WIDTH{1'b0}};
        dsp_s_axi_arvalid_o= 1'b0;
        dsp_s_axi_rready_o = 1'b0; // Default: not ready to accept rvalid

        dsp_mem_rdata_o = {DSP_MEM_DATA_WIDTH{1'b0}};
        dsp_mem_ack_o   = 1'b0;

        // CPU to DATA_MEM Path
        if (cpu_granted_data_mem_w) begin
            // Assuming DATA_MEM addr_i is word index. CPU address is byte.
            // For MEM_ADDR_WIDTH=8 (256 words), word addr is cpu_addr[9:2]
            dm_addr_o  = cpu_mem_addr_i[MEM_ADDR_WIDTH-1+2 : 2];
            dm_wdata_o = cpu_mem_wdata_i;
            dm_we_o    = cpu_mem_we_i;
            if (cpu_mem_re_i && !cpu_mem_we_i) begin // CPU Read
                cpu_mem_rdata_o = dm_rdata_i;
            end
            cpu_mem_ack_o = 1'b1; // Simple single-cycle ack for DATA_MEM
        end
        // DSP to DATA_MEM Path
        else if (dsp_granted_data_mem_w) begin
            // Assuming DATA_MEM addr_i is word index. DSP address is byte.
            dm_addr_o  = dsp_mem_addr_i[MEM_ADDR_WIDTH-1+2 : 2];
            dm_wdata_o = dsp_mem_wdata_i;
            dm_we_o    = dsp_mem_we_i;
            if (!dsp_mem_we_i) begin // DSP Read
                dsp_mem_rdata_o = dm_rdata_i;
            end
            dsp_mem_ack_o = 1'b1; // Simple single-cycle ack for DATA_MEM
        end

        // CPU to DSP Registers Path
        if (cpu_access_dsp_regs_w) begin
            // Pass through address and data for AXI write/read to DSP
            // Lower bits of CPU address map to DSP register address space
            dsp_s_axi_awaddr_o = cpu_mem_addr_i[DSP_REG_ADDR_WIDTH-1:0];
            dsp_s_axi_araddr_o = cpu_mem_addr_i[DSP_REG_ADDR_WIDTH-1:0];
            dsp_s_axi_wdata_o  = cpu_mem_wdata_i;
            dsp_s_axi_wstrb_o  = {(CPU_DATA_WIDTH/8){1'b1}}; // Assuming full word write for registers

            if (cpu_mem_we_i) begin // CPU Write to DSP
                dsp_s_axi_awvalid_o = 1'b1; // Assert AXI AWVALID
                dsp_s_axi_wvalid_o  = 1'b1; // Assert AXI WVALID
            end else if (cpu_mem_re_i) begin // CPU Read from DSP
                dsp_s_axi_arvalid_o = 1'b1; // Assert AXI ARVALID
            end

            // Handle AXI Read Data Path from DSP
            if (dsp_s_axi_rvalid_i) begin
                cpu_mem_rdata_o = dsp_s_axi_rdata_i;
                dsp_s_axi_rready_o = 1'b1; // Tell DSP we took the read data
            end

            // Handle AXI Write Response Path from DSP
            if (dsp_s_axi_bvalid_i) begin
                dsp_s_axi_bready_o = 1'b1; // Tell DSP we received the write response
            end

            // For this initial structure, cpu_mem_ack_o for DSP is 0.
            // A proper AXI FSM bridge is needed here for multi-cycle ack.
            // For now, CPU will stall on DSP access until FSM is added.
            // However, if we want to test basic register access with a multi-cycle assumption:
            // A write ack could be when bvalid is received.
            // A read ack could be when rvalid is received.
            // This is still simplified and needs an FSM for robustness.
            // Let's keep cpu_mem_ack_o = 0 for DSP access for this subtask.
             cpu_mem_ack_o = 1'b0;
             // If DSP AXI slave is ready and valid is high, it means transaction is progressing
             // This is NOT a substitute for a proper AXI bridge FSM.
             if (cpu_mem_we_i && dsp_s_axi_awready_i && dsp_s_axi_wready_i && dsp_s_axi_bvalid_i) begin
                 // cpu_mem_ack_o = 1'b1; // Tentative: ack after bvalid
             end else if (cpu_mem_re_i && dsp_s_axi_arready_i && dsp_s_axi_rvalid_i) begin
                 // cpu_mem_ack_o = 1'b1; // Tentative: ack after rvalid
             end

        end
    end

    // Reset handling for registered outputs if any (most are combinational based on inputs)
    // cpu_mem_ack_o, dsp_mem_ack_o are main registered outputs that might need reset.
    // However, they are driven by combinational logic above.
    // The AXI output signals (dsp_s_axi_*) are also combinational based on current CPU request.

endmodule
