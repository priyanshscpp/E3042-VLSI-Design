/*
The instruction fetch unit has clock and reset pins as input and 32-bit instruction code as output.
Internally the block has Instruction Memory, Program Counter(P.C) and an adder to increment counter by 4, 
on every positive clock edge.
*/
`include "INST_MEM.v"

module IFU(
    input clock,reset,
    input stall_pipeline_i, // New stall input
    output [31:0] Instruction_Code
);
reg [31:0] PC = 32'b0;  // 32-bit program counter is initialized to zero

    // Initializing the instruction memory block
    INST_MEM instr_mem(PC,reset,Instruction_Code);

    always @(posedge clock, posedge reset)
    begin
        if(reset == 1)  //If reset is one, clear the program counter
            PC <= 0;
        else if (!stall_pipeline_i) // Only update PC if not stalled
            PC <= PC+4;   // Increment program counter on positive clock edge
        // else PC remains unchanged due to stall
    end

endmodule
