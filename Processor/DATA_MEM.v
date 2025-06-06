module DATA_MEM #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8, // Results in 2^8 = 256 locations
    parameter MEM_DEPTH = 1 << ADDR_WIDTH
)(
    input clock,
    input reset,
    input [ADDR_WIDTH-1:0] addr_i,
    input [DATA_WIDTH-1:0] wdata_i,
    input we_i, // Write enable
    // input re_i, // Read enable (can be implicit)
    output reg [DATA_WIDTH-1:0] rdata_o
);

    // Declare the memory array
    reg [DATA_WIDTH-1:0] memory_array [0:MEM_DEPTH-1];
    integer i; // For initialization loop

    // Synchronous write
    // Asynchronous read (combinational)
    // Optional reset initialization
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                memory_array[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (we_i) begin
            memory_array[addr_i] <= wdata_i;
        end
    end

    always @(*) begin
        // Combinational read: data is available based on current address
        // No explicit read enable 're_i' needed for the memory_array access itself,
        // bus control logic outside will manage when rdata_o is considered valid.
        rdata_o = memory_array[addr_i];
    end

endmodule
