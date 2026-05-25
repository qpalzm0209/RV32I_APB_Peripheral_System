`timescale 1ns / 1ps

module instruction_mem (
    input  [31:0] instr_addr,
    output [31:0] instr_data
);

    logic [31:0] rom[0:127];

    initial begin
        $readmemh("riscv_prg.mem", rom);
        // // Seed negative corner cases for signed/unsigned checks.
        // rom[0]  = 32'hFFF00613; // addi x12, x0, -1
        // rom[1]  = 32'h80000693; // addi x13, x0, -2048
        // 
        // // R-type ALU coverage.
        // rom[2]  = 32'h004182B3; // add  x5,  x3,  x4
        // rom[3]  = 32'h40418333; // sub  x6,  x3,  x4
        // rom[4]  = 32'h004093B3; // sll  x7,  x1,  x4
        // rom[5]  = 32'h00162433; // slt  x8,  x12, x1
        // rom[6]  = 32'h001634B3; // sltu x9,  x12, x1
        // rom[7]  = 32'h0062C533; // xor  x10, x5,  x6
        // rom[8]  = 32'h001655B3; // srl  x11, x12, x1
        // rom[9]  = 32'h40165733; // sra  x14, x12, x1
        // rom[10] = 32'h0062E7B3; // or   x15, x5,  x6
        // rom[11] = 32'h0062F833; // and  x16, x5,  x6
        // 
        // // I-type ALU coverage with signed/unsigned/shift corner cases.
        // rom[12] = 32'h00062893; // slti  x17, x12, 0
        // rom[13] = 32'h00163913; // sltiu x18, x12, 1
        // rom[14] = 32'h0FF2C993; // xori  x19, x5, 255
        // rom[15] = 32'h07F06A13; // ori   x20, x0, 127
        // rom[16] = 32'h00F67A93; // andi  x21, x12, 15
        // rom[17] = 32'h00409B13; // slli  x22, x1, 4
        // rom[18] = 32'h00465B93; // srli  x23, x12, 4
        // rom[19] = 32'h40465C13; // srai  x24, x12, 4
        // 
        // // Store/load width coverage with sign-extension checks.
        // rom[20] = 32'h00C10023; // sb   x12, 0(x2)
        // rom[21] = 32'h00C11123; // sh   x12, 2(x2)
        // rom[22] = 32'h00512223; // sw   x5,  4(x2)
        // rom[23] = 32'h00010C83; // lb   x25, 0(x2)
        // rom[24] = 32'h00014D03; // lbu  x26, 0(x2)
        // rom[25] = 32'h00211D83; // lh   x27, 2(x2)
        // rom[26] = 32'h00215E03; // lhu  x28, 2(x2)
        // rom[27] = 32'h00412E83; // lw   x29, 4(x2)
        // 
        // // Branch coverage. Each branch skips the following addi when taken.
        // rom[28] = 32'h00CC8463; // beq  x25, x12, +8   (taken)
        // rom[29] = 32'h07B00F13; // addi x30, x0, 123   (must be skipped)
        // rom[30] = 32'h00CD1463; // bne  x26, x12, +8   (taken)
        // rom[31] = 32'h001F0F13; // addi x30, x30, 1    (must be skipped)
        // rom[32] = 32'h00C6C463; // blt  x13, x12, +8   (taken)
        // rom[33] = 32'h03700F93; // addi x31, x0, 55    (must be skipped)
        // rom[34] = 32'h00D65463; // bge  x12, x13, +8   (taken)
        // rom[35] = 32'h001F8F93; // addi x31, x31, 1    (must be skipped)
        // rom[36] = 32'h00C0E463; // bltu x1,  x12, +8   (taken)
        // rom[37] = 32'h002F0F13; // addi x30, x30, 2    (must be skipped)
        // rom[38] = 32'h00167463; // bgeu x12, x1,  +8   (taken)
        // rom[39] = 32'h002F8F93; // addi x31, x31, 2    (must be skipped)
        // 
        // // Final sentinels. If all branches above are taken, both stay zero.
        // rom[40] = 32'h00000F13; // addi x30, x0, 0
        // rom[41] = 32'h00000F93; // addi x31, x0, 0
        // 
        // // U/J/JALR coverage.
        // rom[42] = 32'h123452B7; // lui   x5,  0x12345
        // rom[43] = 32'h00001317; // auipc x6,  0x00001
        // rom[44] = 32'h008003EF; // jal   x7,  +8
        // rom[45] = 32'h06300413; // addi  x8,  x0, 99   (must be skipped)
        // rom[46] = 32'h00100493; // addi  x9,  x0, 1
        // rom[47] = 32'h0D000593; // addi  x11, x0, 208
        // rom[48] = 32'h00058567; // jalr  x10, x11, 0
        // rom[49] = 32'h04D00613; // addi  x12, x0, 77   (must be skipped)
        // rom[50] = 32'h00C00693; // addi  x13, x0, 12
        // 
        // for (int idx = 51; idx < 64; idx = idx + 1) begin
        //     rom[idx] = 32'h00000013; // nop
        // end
    end

    assign instr_data = rom[instr_addr[31:2]];

endmodule
