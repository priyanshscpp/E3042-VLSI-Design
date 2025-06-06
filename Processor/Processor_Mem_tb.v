`timescale 1ns / 1ps
`include "PROCESSOR.v" // Will include all other necessary modules

module Processor_Mem_tb;

    // Inputs
    reg clock;
    reg reset;

    // Outputs
    wire zero_flag_tb; // from PROCESSOR

    // Instantiate the Unit Under Test (UUT)
    PROCESSOR uut (
        .clock(clock),
        .reset(reset),
        .zero(zero_flag_tb)
    );

    // Clock generation
    initial begin
        clock = 0;
        forever #5 clock = ~clock; // 10ns period, 100MHz
    end

    // Test sequence
    initial begin
        //1. Initialize Inputs
        reset = 1;
        #20; // Hold reset for a bit

        //2. Release reset
        reset = 0;
        #10; // Wait for PC to start incrementing

        // Instructions executing:
        // PC=0: SW x5, 0(x0)   (x5 should be 0x5 from REG_FILE reset)
        // PC=4: LW x6, 0(x0)   (x6 should become 0x5)
        // PC=8: ADD x7, x6, x0 (x7 should become 0x5)
        // PC=12: NOP
        // PC=16: NOP

        // Let the processor run for enough cycles for these instructions
        // Each instruction takes roughly 1 cycle in this simple model after fetch.
        // Fetch (IFU) + Decode/Execute (Control/Datapath)
        // SW needs: IF, DEC, EX (addr calc), MEM (write)
        // LW needs: IF, DEC, EX (addr calc), MEM (read), WB (write to reg)
        // ADD needs: IF, DEC, EX, WB
        // Let's wait for ~15 clock cycles after reset release.
        #150;

        //3. Verification
        // Check Data Memory Content (after SW)
        // data_memory_module is inside PROCESSOR.uut.data_memory_module
        // memory_array is inside data_memory_module.memory_array
        // Address 0 for SW was mem_addr_w[7:0] = 0.
        if (uut.data_memory_module.memory_array[0] === 32'h00000005) begin
            $display("PASSED: SW instruction stored x5 (0x5) correctly into DATA_MEM[0].");
        end else begin
            $display("FAILED: SW instruction. DATA_MEM[0] = %h, Expected = %h", uut.data_memory_module.memory_array[0], 32'h00000005);
        end

        // Check Register File Content (after LW)
        // Register x6 (index 6) should now have the value loaded from memory (0x5)
        // reg_file_module is inside PROCESSOR.uut.datapath_module.reg_file_module
        // reg_memory is inside reg_file_module.reg_memory
        if (uut.datapath_module.reg_file_module.reg_memory[6] === 32'h00000005) begin
            $display("PASSED: LW instruction loaded value from DATA_MEM[0] into x6 correctly.");
        end else begin
            $display("FAILED: LW instruction. x6 = %h, Expected = %h", uut.datapath_module.reg_file_module.reg_memory[6], 32'h00000005);
        end

        // Check Register File Content (after ADD)
        // Register x7 (index 7) should now have the value from x6 (0x5)
        if (uut.datapath_module.reg_file_module.reg_memory[7] === 32'h00000005) begin
            $display("PASSED: ADD instruction x7 = x6 + x0 resulted in 0x5.");
        end else begin
            $display("FAILED: ADD instruction. x7 = %h, Expected = %h", uut.datapath_module.reg_file_module.reg_memory[7], 32'h00000005);
        end

        $display("Simulation Finished.");
        $finish;
    end

endmodule
