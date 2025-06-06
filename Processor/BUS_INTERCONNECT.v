module BUS_INTERCONNECT #(
    parameter CPU_DATA_WIDTH = 32,
    parameter CPU_ADDR_WIDTH = 32,
    parameter MEM_ADDR_WIDTH = 8, // For DATA_MEM, e.g., 2^8 = 256 words
    parameter CONV_DSP_REG_ADDR_WIDTH = 5, // For Conv DSP AXI-Lite
    parameter DSP_MEM_DATA_WIDTH = 32, // Generic for DSP mem access, can be reused
    // New Parameters for Dot Product DSP
    parameter DSP_DP_REG_ADDR_WIDTH = 5, // For Dot Product DSP AXI-Lite
    parameter DSP_DP_REG_BASE_ADDR = 32'h80000100, // Dot Product DSP registers base
    localparam DSP_DP_REG_SPACE_BYTES = 1 << DSP_DP_REG_ADDR_WIDTH,
    localparam DSP_DP_REG_END_ADDR = DSP_DP_REG_BASE_ADDR + DSP_DP_REG_SPACE_BYTES - 1, // e.g., 0x8000011F

    localparam NUM_DATA_MEM_WORDS = 1 << MEM_ADDR_WIDTH,
    localparam DATA_MEM_SIZE_BYTES = NUM_DATA_MEM_WORDS * (CPU_DATA_WIDTH/8),
    parameter DATA_MEM_BASE_ADDR = 32'h00000000,
    parameter DATA_MEM_END_ADDR = DATA_MEM_BASE_ADDR + DATA_MEM_SIZE_BYTES - 1, // e.g., 0x000_03FF for 256 words

    localparam CONV_DSP_REG_SPACE_BYTES = 1 << CONV_DSP_REG_ADDR_WIDTH,
    parameter CONV_DSP_REG_BASE_ADDR = 32'h80000000, // Base for Convolution DSP
    parameter CONV_DSP_REG_END_ADDR = CONV_DSP_REG_BASE_ADDR + CONV_DSP_REG_SPACE_BYTES - 1 // e.g., 0x8000001F
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

    // Convolution DSP Registers AXI-Lite Slave Interface (to DSP_CONV1D)
    output reg [CONV_DSP_REG_ADDR_WIDTH-1:0] conv_s_axi_awaddr_o,
    output reg conv_s_axi_awvalid_o,
    input conv_s_axi_awready_i,
    output reg [CPU_DATA_WIDTH-1:0] conv_s_axi_wdata_o,
    output reg [CPU_DATA_WIDTH/8-1:0] conv_s_axi_wstrb_o,
    output reg conv_s_axi_wvalid_o,
    input conv_s_axi_wready_i,
    input conv_s_axi_bvalid_i,
    output reg conv_s_axi_bready_o,
    input [1:0] conv_s_axi_bresp_i,

    output reg [CONV_DSP_REG_ADDR_WIDTH-1:0] conv_s_axi_araddr_o,
    output reg conv_s_axi_arvalid_o,
    input conv_s_axi_arready_i,
    input [CPU_DATA_WIDTH-1:0] conv_s_axi_rdata_i,
    input [1:0] conv_s_axi_rresp_i,
    input conv_s_axi_rvalid_i,
    output reg conv_s_axi_rready_o,

    // Convolution DSP Memory Master Interface (from DSP_CONV1D, to access DATA_MEM)
    input [CPU_ADDR_WIDTH-1:0] conv_dsp_mem_addr_i,
    output reg [DSP_MEM_DATA_WIDTH-1:0] conv_dsp_mem_rdata_o,
    input conv_dsp_mem_req_i,
    output reg conv_dsp_mem_ack_o,
    input conv_dsp_mem_we_i,
    input [DSP_MEM_DATA_WIDTH-1:0] conv_dsp_mem_wdata_i,

    // Dot Product DSP Registers AXI-Lite Slave Interface
    output reg [DSP_DP_REG_ADDR_WIDTH-1:0] dp_s_axi_awaddr_o,
    output reg dp_s_axi_awvalid_o,
    input dp_s_axi_awready_i,
    output reg [CPU_DATA_WIDTH-1:0] dp_s_axi_wdata_o,
    output reg [CPU_DATA_WIDTH/8-1:0] dp_s_axi_wstrb_o,
    output reg dp_s_axi_wvalid_o,
    input dp_s_axi_wready_i,
    input dp_s_axi_bvalid_i,
    output reg dp_s_axi_bready_o,
    input [1:0] dp_s_axi_bresp_i,
    output reg [DSP_DP_REG_ADDR_WIDTH-1:0] dp_s_axi_araddr_o,
    output reg dp_s_axi_arvalid_o,
    input dp_s_axi_arready_i,
    input [CPU_DATA_WIDTH-1:0] dp_s_axi_rdata_i,
    input [1:0] dp_s_axi_rresp_i,
    input dp_s_axi_rvalid_i,
    output reg dp_s_axi_rready_o,

    // Dot Product DSP Memory Master Interface
    input [CPU_ADDR_WIDTH-1:0] dp_dsp_mem_addr_i,
    output reg [DSP_MEM_DATA_WIDTH-1:0] dp_dsp_mem_rdata_o,
    input dp_dsp_mem_req_i,
    output reg dp_dsp_mem_ack_o,
    input dp_dsp_mem_we_i,
    input [DSP_MEM_DATA_WIDTH-1:0] dp_dsp_mem_wdata_i
);

    // Address Decoding
    wire cpu_req_active_w = cpu_mem_re_i || cpu_mem_we_i;
    wire cpu_access_data_mem_w = cpu_req_active_w &&
                                (cpu_mem_addr_i >= DATA_MEM_BASE_ADDR) &&
                                (cpu_mem_addr_i <= DATA_MEM_END_ADDR);

    wire cpu_access_conv_dsp_regs_w = cpu_req_active_w &&
                                (cpu_mem_addr_i >= CONV_DSP_REG_BASE_ADDR) &&
                                (cpu_mem_addr_i <= CONV_DSP_REG_END_ADDR);

    wire cpu_access_dp_dsp_regs_w = cpu_req_active_w && // New
                                (cpu_mem_addr_i >= DSP_DP_REG_BASE_ADDR) &&
                                (cpu_mem_addr_i <= DSP_DP_REG_END_ADDR);

    // Convolution DSP Access to Data Memory
    wire conv_dsp_access_data_mem_w = conv_dsp_mem_req_i &&
                               (conv_dsp_mem_addr_i >= DATA_MEM_BASE_ADDR) &&
                               (conv_dsp_mem_addr_i <= DATA_MEM_END_ADDR);

    // Dot Product DSP Access to Data Memory
    wire dp_dsp_access_data_mem_w = dp_dsp_mem_req_i && // New
                               (dp_dsp_mem_addr_i >= DATA_MEM_BASE_ADDR) &&
                               (dp_dsp_mem_addr_i <= DATA_MEM_END_ADDR);

    // Arbitration for DATA_MEM: CPU > Conv DSP > Dot Product DSP
    wire cpu_granted_data_mem_w = cpu_access_data_mem_w;
    wire conv_dsp_granted_data_mem_w = conv_dsp_access_data_mem_w && !cpu_granted_data_mem_w;
    wire dp_dsp_granted_data_mem_w = dp_dsp_access_data_mem_w && !cpu_granted_data_mem_w && !conv_dsp_granted_data_mem_w; // New


    // Combinational logic for routing and acknowledgements
    always @(*) begin
        // Default assignments
        cpu_mem_rdata_o = {CPU_DATA_WIDTH{1'b0}};
        cpu_mem_ack_o   = 1'b0;

        dm_addr_o       = {MEM_ADDR_WIDTH{1'b0}};
        dm_wdata_o      = {CPU_DATA_WIDTH{1'b0}};
        dm_we_o         = 1'b0;

        // Defaults for Convolution DSP AXI-Lite slave signals
        conv_s_axi_awaddr_o = {CONV_DSP_REG_ADDR_WIDTH{1'b0}};
        conv_s_axi_awvalid_o= 1'b0;
        conv_s_axi_wdata_o  = {CPU_DATA_WIDTH{1'b0}};
        conv_s_axi_wstrb_o  = {(CPU_DATA_WIDTH/8){1'b0}};
        conv_s_axi_wvalid_o = 1'b0;
        conv_s_axi_bready_o = 1'b0;
        conv_s_axi_araddr_o = {CONV_DSP_REG_ADDR_WIDTH{1'b0}};
        conv_s_axi_arvalid_o= 1'b0;
        conv_s_axi_rready_o = 1'b0;

        // Defaults for Convolution DSP memory master signals
        conv_dsp_mem_rdata_o = {DSP_MEM_DATA_WIDTH{1'b0}};
        conv_dsp_mem_ack_o   = 1'b0;

        // Defaults for Dot Product DSP AXI-Lite slave signals (New)
        dp_s_axi_awaddr_o  = {DSP_DP_REG_ADDR_WIDTH{1'b0}};
        dp_s_axi_awvalid_o = 1'b0;
        dp_s_axi_wdata_o   = {CPU_DATA_WIDTH{1'b0}};
        dp_s_axi_wstrb_o   = {(CPU_DATA_WIDTH/8){1'b0}};
        dp_s_axi_wvalid_o  = 1'b0;
        dp_s_axi_bready_o  = 1'b0;
        dp_s_axi_araddr_o  = {DSP_DP_REG_ADDR_WIDTH{1'b0}};
        dp_s_axi_arvalid_o = 1'b0;
        dp_s_axi_rready_o  = 1'b0;

        // Defaults for Dot Product DSP memory master signals (New)
        dp_dsp_mem_rdata_o = {DSP_MEM_DATA_WIDTH{1'b0}};
        dp_dsp_mem_ack_o   = 1'b0;


        // DATA_MEM Access Muxing & Control
        if (cpu_granted_data_mem_w) begin
            dm_addr_o  = cpu_mem_addr_i[MEM_ADDR_WIDTH-1+2 : 2];
            dm_wdata_o = cpu_mem_wdata_i;
            dm_we_o    = cpu_mem_we_i;
            if (cpu_mem_re_i && !cpu_mem_we_i) begin
                cpu_mem_rdata_o = dm_rdata_i;
            end
            cpu_mem_ack_o = 1'b1;
        end else if (conv_dsp_granted_data_mem_w) begin
            dm_addr_o  = conv_dsp_mem_addr_i[MEM_ADDR_WIDTH-1+2 : 2];
            dm_wdata_o = conv_dsp_mem_wdata_i;
            dm_we_o    = conv_dsp_mem_we_i;
            if (!conv_dsp_mem_we_i) begin
                conv_dsp_mem_rdata_o = dm_rdata_i;
            end
            conv_dsp_mem_ack_o = 1'b1;
        end else if (dp_dsp_granted_data_mem_w) begin // New: Dot Product DSP access to DATA_MEM
            dm_addr_o  = dp_dsp_mem_addr_i[MEM_ADDR_WIDTH-1+2 : 2];
            dm_wdata_o = dp_dsp_mem_wdata_i;
            dm_we_o    = dp_dsp_mem_we_i;
            if (!dp_dsp_mem_we_i) begin // Read by Dot Product DSP
                dp_dsp_mem_rdata_o = dm_rdata_i;
            end
            dp_dsp_mem_ack_o = 1'b1;
        end

        // CPU to Peripheral Registers Path
        if (cpu_access_conv_dsp_regs_w) begin
            conv_s_axi_awaddr_o = cpu_mem_addr_i[CONV_DSP_REG_ADDR_WIDTH-1:0];
            conv_s_axi_araddr_o = cpu_mem_addr_i[CONV_DSP_REG_ADDR_WIDTH-1:0];
            conv_s_axi_wdata_o  = cpu_mem_wdata_i;
            conv_s_axi_wstrb_o  = {(CPU_DATA_WIDTH/8){1'b1}};

            if (cpu_mem_we_i) begin
                conv_s_axi_awvalid_o = 1'b1;
                conv_s_axi_wvalid_o  = 1'b1;
            end else if (cpu_mem_re_i) begin
                conv_s_axi_arvalid_o = 1'b1;
            end

            if (conv_s_axi_rvalid_i) begin
                cpu_mem_rdata_o = conv_s_axi_rdata_i; // Route read data to CPU
                conv_s_axi_rready_o = 1'b1;
            end

            if (conv_s_axi_bvalid_i) begin
                conv_s_axi_bready_o = 1'b1;
            end

            cpu_mem_ack_o = 1'b0; // CPU stalls for Conv DSP access (no AXI bridge FSM here)
        end
        else if (cpu_access_dp_dsp_regs_w) begin // New: CPU to Dot Product DSP Registers Path
            dp_s_axi_awaddr_o = cpu_mem_addr_i[DSP_DP_REG_ADDR_WIDTH-1:0];
            dp_s_axi_araddr_o = cpu_mem_addr_i[DSP_DP_REG_ADDR_WIDTH-1:0];
            dp_s_axi_wdata_o  = cpu_mem_wdata_i;
            dp_s_axi_wstrb_o  = {(CPU_DATA_WIDTH/8){1'b1}};

            if (cpu_mem_we_i) begin // CPU Write to Dot Product DSP
                dp_s_axi_awvalid_o = 1'b1;
                dp_s_axi_wvalid_o  = 1'b1;
            end else if (cpu_mem_re_i) begin // CPU Read from Dot Product DSP
                dp_s_axi_arvalid_o = 1'b1;
            end

            if (dp_s_axi_rvalid_i) begin
                cpu_mem_rdata_o = dp_s_axi_rdata_i; // Route read data to CPU
                dp_s_axi_rready_o = 1'b1;
            end

            if (dp_s_axi_bvalid_i) begin
                dp_s_axi_bready_o = 1'b1;
            end

            cpu_mem_ack_o = 1'b0; // CPU stalls for Dot Product DSP access
        end
    end

    // Reset handling for registered outputs if any (most are combinational based on inputs)
    // cpu_mem_ack_o, dsp_mem_ack_o are main registered outputs that might need reset.
    // However, they are driven by combinational logic above.
    // The AXI output signals (dsp_s_axi_*) are also combinational based on current CPU request.

endmodule
