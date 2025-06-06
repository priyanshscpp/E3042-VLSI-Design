`timescale 1ns / 1ps
`include "PROCESSOR.v" // This should pull in all other necessary modules

module Processor_CDSP_tb;
    reg clock;
    reg reset;
    wire zero_flag_tb;

    PROCESSOR uut (
        .clock(clock),
        .reset(reset),
        .zero(zero_flag_tb)
    );

    initial begin
        clock = 0;
        forever #5 clock = ~clock; // 100MHz clock period 10ns
    end

    initial begin
        reset = 1;
        #20; // Assert reset for 20ns
        reset = 0;

        // Allow time for C program to execute.
        // This duration needs to be long enough for:
        // 1. CPU to initialize data in DATA_MEM.
        // 2. CPU to configure DSP registers.
        // 3. DSP to perform convolution.
        // 4. CPU to poll DSP status and read results.
        // 5. CPU to perform software verification and write signature.
        #60000; // Increased wait time to 60,000 ns (60 us)

        // Check signature written by C program to DATA_MEM
        // C code writes to address 0x3FC (word 255 if DATA_MEM ADDR_WIDTH=8 for words)
        // DATA_MEM.memory_array index is word index.
        // 0x50415353 for PASS ('PASS')
        // 0x4641494C for FAIL ('FAIL')
        // Note: DATA_MEM ADDR_WIDTH is 8, meaning 256 words. Index 255 is the last word.
        if (uut.data_memory_module.memory_array[255] === 32'h50415353) begin
             $display("PASSED: C Test Program indicated SUCCESS (found 0xPASS_PASS at DATA_MEM[255]).");
        } else if (uut.data_memory_module.memory_array[255] === 32'h4641494C) begin
             $display("FAILED: C Test Program indicated FAILURE (found 0xFAIL_FAIL at DATA_MEM[255]). Actual: %h", uut.data_memory_module.memory_array[255]);
        } else begin
             $display("UNKNOWN: C Test Program result signature not found or incorrect at DATA_MEM[255]. Actual: %h", uut.data_memory_module.memory_array[255]);
        }

        $display("Simulation Finished.");
        $finish;
    end
endmodule
