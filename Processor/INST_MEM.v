module INST_MEM(
    input [31:0] PC, // Still byte address
    input reset,
    output [31:0] Instruction_Code
);
    localparam MEM_SIZE_BYTES = 1024; // 1KB Instruction Memory
    reg [7:0] Memory [0:MEM_SIZE_BYTES-1];
    integer i;

    // Instruction is formed from 4 bytes, little-endian from CPU perspective
    // Memory[PC] is LSB of instruction word
    assign Instruction_Code = {Memory[PC+3], Memory[PC+2], Memory[PC+1], Memory[PC]};

    // Initialize memory (e.g., on reset or as an initial block)
    initial begin // Using initial block for ROM-like behavior
        // In a real scenario, $readmemh or `include would load the program.
        // For now, fill with NOPs (ADDI x0, x0, 0  => 0x00000013)
        // In memory (little-endian bytes for the word 0x00000013):
        // byte+0: 0x13
        // byte+1: 0x00
        // byte+2: 0x00
        // byte+3: 0x00
        for (i = 0; i < MEM_SIZE_BYTES; i = i + 4) begin
            Memory[i]   = 8'h13; // LSB of NOP
            Memory[i+1] = 8'h00;
            Memory[i+2] = 8'h00;
            Memory[i+3] = 8'h00; // MSB of NOP
        end
        // Placeholder for actual program:
        // `include "inst_mem_init.vh"
        // or paste content like:
        // Memory[0] = 8'hXX; // Start of actual program
        // Memory[1] = 8'hYY;
        // ...
    end
endmodule
