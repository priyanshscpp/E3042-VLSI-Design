/* 
Instruction memory takes in two inputs: A 32-bit Program counter and a 1-bit reset. 
The memory is initialized when reset is 1.
When reset is set to 0, Based on the value of PC, corresponding 32-bit Instruction code is output
*/
module INST_MEM(
    input [31:0] PC,
    input reset,
    output [31:0] Instruction_Code
);
    reg [7:0] Memory [31:0]; // Byte addressable memory with 32 locations

    // Under normal operation (reset = 0), we assign the instr. code, based on PC
    assign Instruction_Code = {Memory[PC+3],Memory[PC+2],Memory[PC+1],Memory[PC]};

    // Initializing memory when reset is one
    always @(reset)
    begin
        if(reset == 1)
        begin
            // Test instructions for LW/SW
            // PC = 0: SW x5, 0(x0) (Store value of register x5 (initialized to 0x5) to memory address 0). Hex: 0x00502023
            Memory[3] = 8'h00; Memory[2] = 8'h50; Memory[1] = 8'h20; Memory[0] = 8'h23;

            // PC = 4: LW x6, 0(x0) (Load value from memory address 0 into register x6). Hex: 0x00002303
            Memory[7] = 8'h00; Memory[6] = 8'h00; Memory[5] = 8'h23; Memory[4] = 8'h03;

            // PC = 8: ADD x7, x6, x0 (x7 = x6 + x0, to check if x6 has the loaded value). Hex: 0x000303B3
            Memory[11] = 8'h00; Memory[10] = 8'h03; Memory[9] = 8'h03; Memory[8] = 8'hb3;

            // PC = 12: NOP (ADDI x0, x0, 0). Hex: 0x00000013
            Memory[15] = 8'h00; Memory[14] = 8'h00; Memory[13] = 8'h00; Memory[12] = 8'h13;

            // PC = 16: NOP (ADDI x0, x0, 0). Hex: 0x00000013
            Memory[19] = 8'h00; Memory[18] = 8'h00; Memory[17] = 8'h00; Memory[16] = 8'h13;

            // Original instructions (will be partly overwritten or shifted if addresses conflict)
            // Setting 32-bit instruction: add t1, s0,s1 => 0x00940333 
            // Memory[3] = 8'h00; // Overwritten by SW
            // Memory[2] = 8'h94; // Overwritten by SW
            // Memory[1] = 8'h03; // Overwritten by SW
            // Memory[0] = 8'h33; // Overwritten by SW

            // Setting 32-bit instruction: sub t2, s2, s3 => 0x413903b3
            // Memory[7] = 8'h41; // Overwritten by LW
            // Memory[6] = 8'h39; // Overwritten by LW
            // Memory[5] = 8'h03; // Overwritten by LW
            // Memory[4] = 8'hb3; // Overwritten by LW

            // Setting 32-bit instruction: mul t0, s4, s5 => 0x035a02b3
            // Memory[11] = 8'h03; // Overwritten by ADD
            // Memory[10] = 8'h5a; // Overwritten by ADD
            // Memory[9] = 8'h02;  // Overwritten by ADD
            // Memory[8] = 8'hb3;  // Overwritten by ADD

            // Setting 32-bit instruction: xor t3, s6, s7 => 0x017b4e33
            // Memory[15] = 8'h01; // Overwritten by NOP
            // Memory[14] = 8'h7b; // Overwritten by NOP
            // Memory[13] = 8'h4e; // Overwritten by NOP
            // Memory[12] = 8'h33; // Overwritten by NOP

            // Setting 32-bit instruction: sll t4, s8, s9
            // Memory[19] = 8'h01; // Overwritten by NOP
            // Memory[18] = 8'h9c; // Overwritten by NOP
            // Memory[17] = 8'h1e; // Overwritten by NOP
            // Memory[16] = 8'hb3; // Overwritten by NOP

            // These instructions are at higher addresses and will not be affected by the new ones.
            // Setting 32-bit instruction: srl t5, s10, s11
            Memory[23] = 8'h01;
            Memory[22] = 8'hbd;
            Memory[21] = 8'h5f;
            Memory[20] = 8'h33;
            // Setting 32-bit instruction: and t6, a2, a3
            Memory[27] = 8'h00;
            Memory[26] = 8'hd6;
            Memory[25] = 8'h7f;
            Memory[24] = 8'hb3;
            // Setting 32-bit instruction: or a7, a4, a5
            Memory[31] = 8'h00;
            Memory[30] = 8'hf7;
            Memory[29] = 8'h68;
            Memory[28] = 8'hb3;
        end
    end

endmodule