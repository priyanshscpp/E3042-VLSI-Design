module DSP_CONV1D #(
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ADDR_WIDTH = 5, // Byte address for AXI (2^5 = 32 bytes)
    parameter DSP_DATA_WIDTH = 32,
    // Parameters for array sizes / loop counters
    parameter MAX_CONV_LEN = 256,
    parameter MAX_KERNEL_LEN = 32
)(
    // AXI-Lite Slave Interface (CPU-facing)
    input  s_axi_clk,
    input  s_axi_resetn, // Active low reset

    // Write Address Channel
    input  [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  s_axi_awvalid,
    output reg s_axi_awready,

    // Write Data Channel
    input  [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  s_axi_wvalid,
    output reg s_axi_wready,

    // Write Response Channel
    output reg  s_axi_bvalid,
    input  s_axi_bready,
    output reg [1:0] s_axi_bresp,

    // Read Address Channel
    input  [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  s_axi_arvalid,
    output reg s_axi_arready,

    // Read Data Channel
    output reg [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input  s_axi_rready,

    // DSP Control/Status (Internal Logic to CPU)
    output interrupt_o, // interrupt_o will be a wire assigned below

    // Placeholder Memory Master Interface (for fetching data/kernel & writing results)
    output reg [DSP_DATA_WIDTH-1:0] dsp_mem_addr_o,
    input  [DSP_DATA_WIDTH-1:0] dsp_mem_rdata_i,
    output reg dsp_mem_req_o,
    input  dsp_mem_ack_i,
    output reg dsp_mem_we_o,
    output reg [DSP_DATA_WIDTH-1:0] dsp_mem_wdata_o
);

    // Address Constants (Byte offsets for AXI)
    localparam CTRL_REG_ADDR          = 5'h00; // Control Register (start, int_en)
    localparam STATUS_REG_ADDR        = 5'h04; // Status Register (busy, done, error)
    localparam DATA_IN_ADDR_REG_ADDR  = 5'h08; // Data Input Base Address
    localparam KERNEL_ADDR_REG_ADDR   = 5'h0C; // Kernel Base Address
    localparam DATA_OUT_ADDR_REG_ADDR = 5'h10; // Data Output Base Address
    localparam DATA_LEN_REG_ADDR      = 5'h14; // Data Length
    localparam KERNEL_LEN_REG_ADDR    = 5'h18; // Kernel Length

    // Internal Register Storage
    // Control Register bits
    reg start_r;            // Bit 0 of CTRL_REG
    reg interrupt_enable_r; // Bit 1 of CTRL_REG

    // Status Register bits
    reg busy_r;             // Bit 0 of STATUS_REG
    reg done_r;             // Bit 1 of STATUS_REG
    reg error_r;            // Bit 2 of STATUS_REG

    // Data/Address Registers
    reg [DSP_DATA_WIDTH-1:0] data_in_addr_r;
    reg [DSP_DATA_WIDTH-1:0] kernel_addr_r;
    reg [DSP_DATA_WIDTH-1:0] data_out_addr_r;
    reg [DSP_DATA_WIDTH-1:0] data_len_r;
    reg [DSP_DATA_WIDTH-1:0] kernel_len_r;

    // Internal AXI signals
    reg [AXI_ADDR_WIDTH-1:0] axi_awaddr_r;
    reg [AXI_ADDR_WIDTH-1:0] axi_araddr_r;

    // FSM States
    localparam S_IDLE            = 4'd0;
    localparam S_BUSY_INIT       = 4'd1;
    localparam S_INIT_ACCUM      = 4'd2;
    localparam S_FETCH_KERNEL    = 4'd3;
    localparam S_WAIT_KERNEL_ACK = 4'd4;
    localparam S_FETCH_DATA      = 4'd5;
    localparam S_WAIT_DATA_ACK   = 4'd6;
    localparam S_EXEC_MAC        = 4'd7;
    localparam S_CHECK_MAC_LOOP  = 4'd8;
    localparam S_STORE_OUTPUT    = 4'd9;
    localparam S_WAIT_STORE_ACK  = 4'd10;
    localparam S_CHECK_OUTPUT_LOOP = 4'd11;
    localparam S_FINISH          = 4'd12;
    // localparam S_ERROR_STATE     = 4'd13; // Optional error state

    // FSM Registers
    reg [3:0] current_state_r;
    reg [3:0] next_state_w;

    // Datapath Elements & Control Registers
    reg [DSP_DATA_WIDTH-1:0] current_input_val_r;
    reg [DSP_DATA_WIDTH-1:0] current_kernel_val_r;
    reg [DSP_DATA_WIDTH-1:0] accumulator_r;
    wire [DSP_DATA_WIDTH-1:0] mac_mult_result_w = current_input_val_r * current_kernel_val_r;

    reg [$clog2(MAX_CONV_LEN)-1:0] output_idx_r;
    reg [$clog2(MAX_KERNEL_LEN)-1:0] kernel_idx_r;

    reg [DSP_DATA_WIDTH-1:0] current_data_read_addr_r;
    reg [DSP_DATA_WIDTH-1:0] current_kernel_read_addr_r;
    reg [DSP_DATA_WIDTH-1:0] current_output_write_addr_r;

    wire [DSP_DATA_WIDTH-1:0] calculated_output_len_w = (data_len_r >= kernel_len_r && kernel_len_r > 0) ? (data_len_r - kernel_len_r + 1) : 0;

    // Interrupt line
    assign interrupt_o = (done_r || error_r) && interrupt_enable_r;

    //--------------------------------------------------------------------------
    // AXI-Lite Write Logic
    //--------------------------------------------------------------------------
    // awready logic: Asserted when ready to accept an address. Deasserted if bvalid is high and bready is low.
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin
        if (!s_axi_resetn) begin
            s_axi_awready <= 1'b0;
            axi_awaddr_r  <= {(AXI_ADDR_WIDTH){1'b0}};
        end else begin
            if (s_axi_awready && s_axi_awvalid) begin
                axi_awaddr_r <= s_axi_awaddr; // Latch address
            end
            // s_axi_awready is high unless write response is pending
            if (~(s_axi_bvalid && ~s_axi_bready)) begin
                 s_axi_awready <= 1'b1;
            end else if (s_axi_awvalid && s_axi_awready) begin // Address accepted
                 s_axi_awready <= 1'b0;
            end
        end
    end

    // wready logic: Asserted when ready to accept write data.
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin
        if (!s_axi_resetn) begin
            s_axi_wready <= 1'b0;
        end else begin
            // s_axi_wready is high unless write response is pending
            if (~(s_axi_bvalid && ~s_axi_bready)) begin
                s_axi_wready <= 1'b1;
            end else if (s_axi_wvalid && s_axi_wready) begin // Data accepted
                s_axi_wready <= 1'b0;
            end
        end
    end

    // Write data to registers and bvalid/bresp generation
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin
        if (!s_axi_resetn) begin
            start_r            <= 1'b0;
            interrupt_enable_r <= 1'b0;
            // busy_r is controlled by FSM, done_r, error_r by FSM and this block
            // done_r, error_r are cleared by CPU read of status reg or by new start
            data_in_addr_r     <= 32'b0;
            kernel_addr_r      <= 32'b0;
            data_out_addr_r    <= 32'b0;
            data_len_r         <= 32'b0;
            kernel_len_r       <= 32'b0;
            s_axi_bvalid       <= 1'b0;
            s_axi_bresp        <= 2'b00;
        end else begin
            // Manage bvalid
            if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;       // Respond once data is written
                s_axi_bresp  <= 2'b00;      // OKAY response

                // Decode address and write to registers
                // axi_awaddr_r was latched when awready and awvalid were high
                case (axi_awaddr_r) // Using latched address
                    CTRL_REG_ADDR: begin
                        start_r            <= s_axi_wdata[0]; // FSM will detect this and clear it
                        interrupt_enable_r <= s_axi_wdata[1];
                        // done_r and error_r clearing on start is now handled by FSM S_BUSY_INIT
                    end
                    DATA_IN_ADDR_REG_ADDR:  data_in_addr_r  <= s_axi_wdata;
                    KERNEL_ADDR_REG_ADDR:   kernel_addr_r   <= s_axi_wdata;
                    DATA_OUT_ADDR_REG_ADDR: data_out_addr_r <= s_axi_wdata;
                    DATA_LEN_REG_ADDR:      data_len_r      <= s_axi_wdata;
                    KERNEL_LEN_REG_ADDR:    kernel_len_r    <= s_axi_wdata;
                    // STATUS_REG is read-only, writes are ignored or could set error
                    default: begin
                        // Write to undefined register, could set an error flag or ignore
                    end
                endcase
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0; // Clear bvalid after handshake
            end
        end
    end

    //--------------------------------------------------------------------------
    // AXI-Lite Read Logic
    //--------------------------------------------------------------------------
    // arready logic: Asserted when ready to accept a read address. Deasserted if rvalid is high and rready is low.
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin
        if (!s_axi_resetn) begin
            s_axi_arready <= 1'b0;
            axi_araddr_r  <= {(AXI_ADDR_WIDTH){1'b0}};
        end else begin
            if (s_axi_arready && s_axi_arvalid) begin
                axi_araddr_r <= s_axi_araddr; // Latch read address
            end
            // s_axi_arready is high unless read response is pending
            if (~(s_axi_rvalid && ~s_axi_rready)) begin
                s_axi_arready <= 1'b1;
            end else if (s_axi_arvalid && s_axi_arready) begin // Address accepted
                s_axi_arready <= 1'b0;
            end
        end
    end

    // rdata, rvalid, rresp generation
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin
        if (!s_axi_resetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= 32'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready && !s_axi_rvalid) begin // Addr accepted, and not already sending data
                s_axi_rvalid <= 1'b1;   // Data will be valid in this cycle (or next for registered output)
                s_axi_rresp  <= 2'b00;  // OKAY response

                // Decode read address (using latched axi_araddr_r) and set rdata
                case (axi_araddr_r)
                    CTRL_REG_ADDR:          s_axi_rdata <= {{(AXI_DATA_WIDTH-2){1'b0}}, interrupt_enable_r, start_r};
                    STATUS_REG_ADDR: begin
                        s_axi_rdata <= {{(AXI_DATA_WIDTH-3){1'b0}}, error_r, done_r, busy_r};
                        // Clear done and error flags on read of status register if they were set
                        if (done_r)  done_r  <= 1'b0;
                        if (error_r) error_r <= 1'b0;
                    end
                    DATA_IN_ADDR_REG_ADDR:  s_axi_rdata <= data_in_addr_r;
                    KERNEL_ADDR_REG_ADDR:   s_axi_rdata <= kernel_addr_r;
                    DATA_OUT_ADDR_REG_ADDR: s_axi_rdata <= data_out_addr_r;
                    DATA_LEN_REG_ADDR:      s_axi_rdata <= data_len_r;
                    KERNEL_LEN_REG_ADDR:    s_axi_rdata <= kernel_len_r;
                    default:                s_axi_rdata <= 32'hDEADBEEF; // Or 0, error indicator
                endcase
            end else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid <= 1'b0; // Clear rvalid after handshake
            end
        end
    end

    //--------------------------------------------------------------------------
    // DSP Core FSM - State Register
    //--------------------------------------------------------------------------
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin
        if (!s_axi_resetn) begin
            current_state_r <= S_IDLE;
        end else begin
            current_state_r <= next_state_w;
        end
    end

    //--------------------------------------------------------------------------
    // DSP Core FSM - Next State Logic and Datapath Control
    //--------------------------------------------------------------------------
    always @(*) begin
        // Default assignments for FSM outputs
        next_state_w = current_state_r; // Stay in current state by default

        // Default values for control signals modified by FSM
        // These are important to ensure signals are not unintentionally asserted
        dsp_mem_req_o = 1'b0;
        dsp_mem_we_o  = 1'b0;
        // dsp_mem_addr_o, dsp_mem_wdata_o will be set explicitly in states

        // Note: AXI-controlled registers like start_r, interrupt_enable_r,
        // data_in_addr_r etc. are NOT given default values here as they are set by AXI writes.
        // FSM-controlled status registers (busy_r, done_r, error_r) are set explicitly.

        case (current_state_r)
            S_IDLE: begin
                busy_r = 1'b0; // Not busy in IDLE
                // done_r and error_r retain their values until cleared by AXI read or new start
                if (start_r && !busy_r) begin // Check !busy_r to prevent re-trigger if start is still high
                    next_state_w = S_BUSY_INIT;
                    // start_r is NOT cleared by the FSM. It's a register set by CPU via AXI.
                    // The FSM just reacts to it. CPU can clear it if needed by writing 0.
                end
            end

            S_BUSY_INIT: begin
                busy_r  = 1'b1;
                done_r  = 1'b0;
                error_r = 1'b0;

                if (kernel_len_r == 0 || data_len_r < kernel_len_r) begin
                    error_r = 1'b1; // Set error flag
                    next_state_w = S_FINISH; // Go to finish to report error
                end else begin
                    output_idx_r = 0;
                    current_output_write_addr_r = data_out_addr_r;
                    next_state_w = S_INIT_ACCUM;
                end
            end

            S_INIT_ACCUM: begin
                accumulator_r = {DSP_DATA_WIDTH{1'b0}};
                kernel_idx_r = 0;
                // Calculate starting data address for this output point
                current_data_read_addr_r = data_in_addr_r + output_idx_r;
                current_kernel_read_addr_r = kernel_addr_r;
                next_state_w = S_FETCH_KERNEL;
            end

            S_FETCH_KERNEL: begin
                dsp_mem_addr_o = current_kernel_read_addr_r;
                dsp_mem_req_o  = 1'b1;
                dsp_mem_we_o   = 1'b0; // Read operation
                next_state_w   = S_WAIT_KERNEL_ACK;
            end

            S_WAIT_KERNEL_ACK: begin
                if (dsp_mem_ack_i) begin
                    current_kernel_val_r = dsp_mem_rdata_i;
                    current_kernel_read_addr_r = current_kernel_read_addr_r + 1; // Assuming word addressing
                    dsp_mem_req_o = 1'b0; // De-assert request
                    next_state_w = S_FETCH_DATA;
                end else begin
                    // dsp_mem_req_o should remain asserted if not acked, handled by default assignment
                    dsp_mem_req_o  = 1'b1;
                    next_state_w = S_WAIT_KERNEL_ACK;
                end
            end

            S_FETCH_DATA: begin
                dsp_mem_addr_o = current_data_read_addr_r;
                dsp_mem_req_o  = 1'b1;
                dsp_mem_we_o   = 1'b0; // Read operation
                next_state_w   = S_WAIT_DATA_ACK;
            end

            S_WAIT_DATA_ACK: begin
                if (dsp_mem_ack_i) begin
                    current_input_val_r = dsp_mem_rdata_i;
                    current_data_read_addr_r = current_data_read_addr_r + 1; // Assuming word addressing
                    dsp_mem_req_o = 1'b0; // De-assert request
                    next_state_w = S_EXEC_MAC;
                end else begin
                    dsp_mem_req_o  = 1'b1;
                    next_state_w = S_WAIT_DATA_ACK;
                end
            end

            S_EXEC_MAC: begin
                accumulator_r = accumulator_r + mac_mult_result_w;
                kernel_idx_r = kernel_idx_r + 1;
                next_state_w = S_CHECK_MAC_LOOP;
            end

            S_CHECK_MAC_LOOP: begin
                if (kernel_idx_r < kernel_len_r) begin
                    next_state_w = S_FETCH_KERNEL;
                end else begin
                    next_state_w = S_STORE_OUTPUT;
                end
            end

            S_STORE_OUTPUT: begin
                dsp_mem_addr_o  = current_output_write_addr_r;
                dsp_mem_wdata_o = accumulator_r;
                dsp_mem_req_o   = 1'b1;
                dsp_mem_we_o    = 1'b1; // Write operation
                next_state_w    = S_WAIT_STORE_ACK;
            end

            S_WAIT_STORE_ACK: begin
                if (dsp_mem_ack_i) begin
                    output_idx_r = output_idx_r + 1;
                    current_output_write_addr_r = current_output_write_addr_r + 1; // Assuming word addressing
                    dsp_mem_req_o = 1'b0; // De-assert request
                    dsp_mem_we_o  = 1'b0; // De-assert write enable
                    next_state_w = S_CHECK_OUTPUT_LOOP;
                end else begin
                    dsp_mem_req_o   = 1'b1;
                    dsp_mem_we_o    = 1'b1;
                    next_state_w = S_WAIT_STORE_ACK;
                end
            end

            S_CHECK_OUTPUT_LOOP: begin
                if (output_idx_r < calculated_output_len_w) begin
                    next_state_w = S_INIT_ACCUM;
                end else begin
                    next_state_w = S_FINISH;
                end
            end

            S_FINISH: begin
                done_r = 1'b1; // Signal completion
                busy_r = 1'b0; // No longer busy
                // error_r would have been set in S_BUSY_INIT if invalid params
                next_state_w = S_IDLE;
            end

            default: begin
                // Should not happen, but if it does, go to a safe state
                error_r = 1'b1; // Indicate an FSM error
                next_state_w = S_IDLE;
            end
        endcase
    end

    // Reset logic for FSM controlled signals not covered by AXI reset (if any)
    // busy_r, done_r, error_r are handled by FSM states and AXI interactions.
    // dsp_mem_addr_o, dsp_mem_wdata_o are set by FSM states.
    // dsp_mem_req_o, dsp_mem_we_o are set by FSM states (defaulted to 0 in comb. block).
    // Other datapath regs (current_input_val_r, etc.) are loaded within FSM states.

endmodule
