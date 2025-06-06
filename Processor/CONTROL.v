module CONTROL(
    input [6:0] funct7,
    input [2:0] funct3,
    input [6:0] opcode,
    output reg [3:0] alu_control,
    output reg regwrite_control,
    output reg mem_read_o,
    output reg mem_write_o,
    output reg mem_to_reg_o,
    output reg alu_src_b_o,
    // New ports for stalling
    input mem_ack_i,
    output reg stall_pipeline_o
);
    // Wires for internal logic
    wire is_load_instr_w;
    wire is_store_instr_w;
    wire is_memory_access_w;

    assign is_load_instr_w = (opcode == 7'b0000011);
    assign is_store_instr_w = (opcode == 7'b0100011);
    assign is_memory_access_w = is_load_instr_w || is_store_instr_w;

    always @(funct3 or funct7 or opcode or mem_ack_i or is_memory_access_w) // Added mem_ack_i and derived signal
    begin
        // Default values for all control signals
        alu_control = 4'b0000;      // Default to AND or some other default
        regwrite_control = 0;
        mem_read_o = 0;
        mem_write_o = 0;
        mem_to_reg_o = 0;
        alu_src_b_o = 0;            // Default ALU Src B to register read_data2
        stall_pipeline_o = 1'b0;    // Default stall to false

        if (opcode == 7'b0110011) begin // R-type instructions
            regwrite_control = 1;
            mem_read_o = 0;
            mem_write_o = 0;
            mem_to_reg_o = 0; // Data comes from ALU
            alu_src_b_o = 0;  // ALU's second operand is from register file (read_data2)

            case (funct3)
                0: begin
                    if(funct7 == 0)
                        alu_control = 4'b0010; // ADD
                    else if(funct7 == 32)
                        alu_control = 4'b0100; // SUB
                end
                6: alu_control = 4'b0001; // OR
                7: alu_control = 4'b0000; // AND
                1: alu_control = 4'b0011; // SLL
                5: alu_control = 4'b0101; // SRL
                2: alu_control = 4'b0110; // MUL
                4: alu_control = 4'b0111; // XOR
            endcase
        end
        else if (opcode == 7'b0000011) begin // LW instruction
            regwrite_control = 1;
            mem_read_o = 1;
            mem_write_o = 0;
            mem_to_reg_o = 1;       // Data from memory to register
            alu_control = 4'b0010;  // ADD for address calculation (rs1 + immediate)
            alu_src_b_o = 1;        // ALU's second operand is the sign-extended immediate
        end
        else if (opcode == 7'b0100011) begin // SW instruction
            regwrite_control = 0;   // No register write for SW
            mem_read_o = 0;
            mem_write_o = 1;
            mem_to_reg_o = 0;       // Doesn't matter, regwrite_control is 0
            alu_control = 4'b0010;  // ADD for address calculation (rs1 + immediate)
            alu_src_b_o = 1;        // ALU's second operand is the sign-extended immediate
        end
        // Add other instruction types here if needed, e.g., I-type arithmetic, Jumps, Branches
        // By default, all control signals are set to 0 or a safe state above.

        // Stall logic: Stall if it's a memory access and memory hasn't acknowledged yet.
        if (is_memory_access_w && !mem_ack_i) begin
            stall_pipeline_o = 1'b1;
            // If we are stalling for a LW instruction, we must ensure that regwrite_control
            // related to *this specific LW* is also effectively delayed.
            // The current combinational logic sets regwrite_control=1 for LW.
            // The DATAPATH will need to be modified to use mem_ack_i to qualify the actual write enable
            // to the register file for load operations.
            // For SW, regwrite_control is already 0, so no special handling needed here for it.
            // Other control signals like alu_control, mem_read_o, mem_write_o for the current
            // instruction should remain asserted to keep the memory operation active.
        end else begin
            stall_pipeline_o = 1'b0;
        end
    end

endmodule
