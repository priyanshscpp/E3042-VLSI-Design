module DSP_DOT_PRODUCT #(
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ADDR_WIDTH = 5, // Byte address for AXI (2^5 = 32 bytes)
    parameter DSP_DATA_WIDTH = 32,
    parameter MAX_VECTOR_LEN = 1024 // Max elements in a vector for sizing element_idx_r
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

    // Placeholder Memory Master Interface (for fetching vector data)
    output reg [DSP_DATA_WIDTH-1:0] dsp_mem_addr_o,
    input  [DSP_DATA_WIDTH-1:0] dsp_mem_rdata_i,
    output reg dsp_mem_req_o,
    input  dsp_mem_ack_i,
    output reg dsp_mem_we_o,   // Not strictly needed if only reading for dot product
    output reg [DSP_DATA_WIDTH-1:0] dsp_mem_wdata_o // Not strictly needed
);

    // Address Constants (Byte offsets for AXI)
    localparam CTRL_REG_ADDR          = 5'h00; // Control Register (start, int_en)
    localparam STATUS_REG_ADDR        = 5'h04; // Status Register (busy, done, error)
    localparam VECTOR_A_ADDR_REG_ADDR = 5'h08; // Vector A Base Address
    localparam VECTOR_B_ADDR_REG_ADDR = 5'h0C; // Vector B Base Address
    localparam VECTOR_LEN_REG_ADDR    = 5'h10; // Vector Length (number of elements)
    localparam RESULT_REG_ADDR        = 5'h14; // Dot Product Result Register (Read-Only)

    // Internal Register Storage
    // Control Register bits
    reg start_r;            // Bit 0 of CTRL_REG
    reg interrupt_enable_r; // Bit 1 of CTRL_REG

    // Status Register bits
    reg busy_r;             // Bit 0 of STATUS_REG (Set by FSM)
    reg done_r;             // Bit 1 of STATUS_REG (Set by FSM)
    reg error_r;            // Bit 2 of STATUS_REG (Set by FSM or config error)

    // Data/Address Registers
    reg [DSP_DATA_WIDTH-1:0] vector_a_addr_r;
    reg [DSP_DATA_WIDTH-1:0] vector_b_addr_r;
    reg [DSP_DATA_WIDTH-1:0] vector_len_r;    // Placeholder width, practically needs e.g. $clog2(MAX_LEN)
    reg [DSP_DATA_WIDTH-1:0] result_r;        // Stores the dot product result (written by FSM)

    // Internal AXI signals for latched addresses
    reg [AXI_ADDR_WIDTH-1:0] axi_awaddr_r; // Latched write address
    reg [AXI_ADDR_WIDTH-1:0] axi_araddr_r; // Latched read address

    // FSM States
    localparam S_IDLE         = 4'd0;
    localparam S_BUSY_INIT    = 4'd1;
    localparam S_FETCH_A      = 4'd2;
    localparam S_WAIT_A_ACK   = 4'd3;
    localparam S_FETCH_B      = 4'd4;
    localparam S_WAIT_B_ACK   = 4'd5;
    localparam S_EXEC_MAC     = 4'd6;
    localparam S_CHECK_LOOP   = 4'd7;
    localparam S_FINISH       = 4'd8;

    // FSM Registers
    reg [3:0] current_state_r;
    reg [3:0] next_state_w;

    // Datapath Elements & Control Registers
    reg [DSP_DATA_WIDTH-1:0] current_a_val_r;
    reg [DSP_DATA_WIDTH-1:0] current_b_val_r;
    reg [DSP_DATA_WIDTH-1:0] accumulator_internal_r; // Internal accumulator for sum of products
    wire [DSP_DATA_WIDTH-1:0] product_w = current_a_val_r * current_b_val_r; // Product of current elements

    reg [$clog2(MAX_VECTOR_LEN)-1:0] element_idx_r; // Current element index being processed

    reg [DSP_DATA_WIDTH-1:0] current_a_read_addr_r; // Internal pointer for vector A elements
    reg [DSP_DATA_WIDTH-1:0] current_b_read_addr_r; // Internal pointer for vector B elements

    // Interrupt line
    assign interrupt_o = (done_r || error_r) && interrupt_enable_r;

    //--------------------------------------------------------------------------
    // AXI-Lite Write Logic
    //--------------------------------------------------------------------------
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin // awready logic
        if (!s_axi_resetn) begin
            s_axi_awready <= 1'b0;
            axi_awaddr_r  <= {(AXI_ADDR_WIDTH){1'b0}};
        end else begin
            if (s_axi_awready && s_axi_awvalid) begin // Latch address when valid and ready
                axi_awaddr_r <= s_axi_awaddr;
            end
            // Assert awready unless bvalid is high and bready is low (slave backpressure)
            if (~(s_axi_bvalid && ~s_axi_bready)) begin
                 s_axi_awready <= 1'b1;
            end else if (s_axi_awvalid && s_axi_awready) begin // If accepted this cycle
                 s_axi_awready <= 1'b0; // Deassert for one cycle
            end
        end
    end

    always @(posedge s_axi_clk or negedge s_axi_resetn) begin // wready logic
        if (!s_axi_resetn) begin
            s_axi_wready <= 1'b0;
        end else begin
            // Assert wready unless bvalid is high and bready is low
            if (~(s_axi_bvalid && ~s_axi_bready)) begin
                s_axi_wready <= 1'b1;
            end else if (s_axi_wvalid && s_axi_wready) begin // If accepted this cycle
                s_axi_wready <= 1'b0; // Deassert for one cycle
            end
        end
    end

    always @(posedge s_axi_clk or negedge s_axi_resetn) begin // Register write and bvalid/bresp logic
        if (!s_axi_resetn) begin
            start_r            <= 1'b0;
            interrupt_enable_r <= 1'b0;
            vector_a_addr_r    <= {DSP_DATA_WIDTH{1'b0}};
            vector_b_addr_r    <= {DSP_DATA_WIDTH{1'b0}};
            vector_len_r       <= {DSP_DATA_WIDTH{1'b0}};
            // result_r is written by FSM, not AXI directly, but reset it here.
            result_r           <= {DSP_DATA_WIDTH{1'b0}};
            s_axi_bvalid       <= 1'b0;
            s_axi_bresp        <= 2'b00;
            // done_r, error_r, busy_r are reset by FSM logic/separate reset block
        end else begin
            if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY

                case (axi_awaddr_r) // Use latched address
                    CTRL_REG_ADDR: begin
                        start_r            <= s_axi_wdata[0];
                        interrupt_enable_r <= s_axi_wdata[1];
                        if (s_axi_wdata[0]) begin // If start is asserted by this write
                            done_r  <= 1'b0;      // Clear done status
                            error_r <= 1'b0;      // Clear error status
                            // busy_r will be set by FSM
                        end
                    end
                    VECTOR_A_ADDR_REG_ADDR: vector_a_addr_r <= s_axi_wdata;
                    VECTOR_B_ADDR_REG_ADDR: vector_b_addr_r <= s_axi_wdata;
                    VECTOR_LEN_REG_ADDR:    vector_len_r    <= s_axi_wdata;
                    // STATUS_REG_ADDR and RESULT_REG_ADDR are read-only from AXI perspective
                    default: begin
                        // Write to undefined or read-only register, can be ignored or flag an error
                        // s_axi_bresp <= 2'b10; // SLVERR (optional)
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
    always @(posedge s_axi_clk or negedge s_axi_resetn) begin // arready logic
        if (!s_axi_resetn) begin
            s_axi_arready <= 1'b0;
            axi_araddr_r  <= {(AXI_ADDR_WIDTH){1'b0}};
        end else begin
            if (s_axi_arready && s_axi_arvalid) begin // Latch address when valid and ready
                axi_araddr_r <= s_axi_araddr;
            end
            // Assert arready unless rvalid is high and rready is low
            if (~(s_axi_rvalid && ~s_axi_rready)) begin
                s_axi_arready <= 1'b1;
            end else if (s_axi_arvalid && s_axi_arready) begin // If accepted this cycle
                s_axi_arready <= 1'b0; // Deassert for one cycle
            end
        end
    end

    always @(posedge s_axi_clk or negedge s_axi_resetn) begin // rdata, rvalid, rresp generation
        if (!s_axi_resetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
            s_axi_rdata  <= {AXI_DATA_WIDTH{1'b0}};
        end else begin
            if (s_axi_arvalid && s_axi_arready && !s_axi_rvalid) begin // Addr accepted, and not already sending data
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00; // OKAY

                case (axi_araddr_r) // Use latched read address
                    CTRL_REG_ADDR:          s_axi_rdata <= {{(AXI_DATA_WIDTH-2){1'b0}}, interrupt_enable_r, start_r};
                    STATUS_REG_ADDR: begin
                        s_axi_rdata <= {{(AXI_DATA_WIDTH-3){1'b0}}, error_r, done_r, busy_r};
                        if (done_r)  done_r  <= 1'b0; // Clear done on read
                        if (error_r) error_r <= 1'b0; // Clear error on read
                    end
                    VECTOR_A_ADDR_REG_ADDR: s_axi_rdata <= vector_a_addr_r;
                    VECTOR_B_ADDR_REG_ADDR: s_axi_rdata <= vector_b_addr_r;
                    VECTOR_LEN_REG_ADDR:    s_axi_rdata <= vector_len_r;
                    RESULT_REG_ADDR:        s_axi_rdata <= result_r;
                    default:                s_axi_rdata <= {AXI_DATA_WIDTH{1'hDE}}; // Indicate read from undefined address
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
            // Reset FSM-controlled status registers and memory interface signals
            busy_r          <= 1'b0;
            done_r          <= 1'b0;
            error_r         <= 1'b0; // error_r is also cleared by AXI write to start
            dsp_mem_req_o   <= 1'b0;
            dsp_mem_we_o    <= 1'b0;
            dsp_mem_addr_o  <= {DSP_DATA_WIDTH{1'b0}};
            dsp_mem_wdata_o <= {DSP_DATA_WIDTH{1'b0}};
            // result_r is reset in AXI logic, accumulator_internal_r will be reset on S_BUSY_INIT entry
        end else begin
            current_state_r <= next_state_w;

            // Sequential assignments on state transitions or within states
            if (current_state_r == S_IDLE && next_state_w == S_BUSY_INIT) begin
                busy_r <= 1'b1;
                done_r <= 1'b0; // done_r and error_r are cleared by AXI write to start_r as well
                if (vector_len_r == 0) begin // Check config at the point of starting
                    error_r <= 1'b1;
                end else begin
                    error_r <= 1'b0; // Clear previous error if any, if params are valid now
                end
                result_r <= {DSP_DATA_WIDTH{1'b0}}; // Clear previous result
                accumulator_internal_r <= {DSP_DATA_WIDTH{1'b0}};
                element_idx_r <= 0;
                current_a_read_addr_r <= vector_a_addr_r;
                current_b_read_addr_r <= vector_b_addr_r;
            end

            if (current_state_r == S_WAIT_A_ACK && dsp_mem_ack_i) begin
                current_a_val_r <= dsp_mem_rdata_i;
                current_a_read_addr_r <= current_a_read_addr_r + 1; // Assuming word addressing
            end
            if (current_state_r == S_WAIT_B_ACK && dsp_mem_ack_i) begin
                current_b_val_r <= dsp_mem_rdata_i;
                current_b_read_addr_r <= current_b_read_addr_r + 1; // Assuming word addressing
            end
            if (current_state_r == S_EXEC_MAC) begin
                accumulator_internal_r <= accumulator_internal_r + product_w;
                element_idx_r <= element_idx_r + 1;
            end

            if (next_state_w == S_FINISH && current_state_r != S_FINISH) begin // When transitioning TO S_FINISH
                result_r <= accumulator_internal_r;
                done_r   <= 1'b1;
                busy_r   <= 1'b0;
            end

            // If FSM is reset to IDLE, ensure busy is also reset
            if (next_state_w == S_IDLE && current_state_r != S_IDLE) begin
                 busy_r <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // DSP Core FSM - Next State Logic and Combinational Outputs
    //--------------------------------------------------------------------------
    always @(*) begin
        // Default assignments
        next_state_w    = current_state_r;
        dsp_mem_req_o   = 1'b0;
        dsp_mem_we_o    = 1'b0;
        dsp_mem_addr_o  = {DSP_DATA_WIDTH{1'b0}}; // Default address
        dsp_mem_wdata_o = {DSP_DATA_WIDTH{1'b0}}; // Default write data

        case (current_state_r)
            S_IDLE: begin
                if (start_r && !busy_r) begin // Note: busy_r is from register, reflects previous cycle's state
                    next_state_w = S_BUSY_INIT;
                end
            end

            S_BUSY_INIT: begin
                // Sequential block handles register updates on S_IDLE -> S_BUSY_INIT transition
                // including error check for vector_len_r == 0.
                if (error_r) begin // If error was set during transition to S_BUSY_INIT
                    next_state_w = S_FINISH;
                end else begin
                    next_state_w = S_FETCH_A;
                end
            end

            S_FETCH_A: begin
                dsp_mem_addr_o = current_a_read_addr_r;
                dsp_mem_req_o  = 1'b1;
                dsp_mem_we_o   = 1'b0; // Read operation
                next_state_w   = S_WAIT_A_ACK;
            end

            S_WAIT_A_ACK: begin
                dsp_mem_req_o = 1'b1; // Keep request asserted until ack
                if (dsp_mem_ack_i) begin
                    // current_a_val_r and current_a_read_addr_r update in clocked block
                    dsp_mem_req_o = 1'b0; // De-assert request for next cycle (will be re-asserted if needed)
                    next_state_w = S_FETCH_B;
                end else begin
                    dsp_mem_req_o = 1'b1; // Keep request asserted
                end
            end

            S_FETCH_B: begin
                dsp_mem_addr_o = current_b_read_addr_r;
                dsp_mem_req_o  = 1'b1;
                dsp_mem_we_o   = 1'b0; // Read operation
                next_state_w   = S_WAIT_B_ACK;
            end

            S_WAIT_B_ACK: begin
                if (dsp_mem_ack_i) begin
                    // current_b_val_r and current_b_read_addr_r update in clocked block
                    dsp_mem_req_o = 1'b0; // De-assert request for next cycle
                    next_state_w = S_EXEC_MAC;
                end else begin
                    dsp_mem_req_o = 1'b1; // Keep request asserted
                end
            end

            S_EXEC_MAC: begin
                // accumulator_internal_r and element_idx_r update in clocked block
                next_state_w = S_CHECK_LOOP;
            end

            S_CHECK_LOOP: begin
                // element_idx_r is already incremented from S_EXEC_MAC
                if (element_idx_r < vector_len_r) begin
                    next_state_w = S_FETCH_A;
                end else begin
                    next_state_w = S_FINISH;
                end
            end

            S_FINISH: begin
                // result_r, done_r, busy_r are updated in the clocked block
                next_state_w = S_IDLE;
            end

            default: begin
                // This case should ideally not be reached if FSM is correct.
                // error_r is set in clocked block if state becomes undefined.
                next_state_w = S_IDLE;
            end
        endcase
    end

    // Removed separate error_r setting block; it's integrated into main FSM clocked block.

endmodule
