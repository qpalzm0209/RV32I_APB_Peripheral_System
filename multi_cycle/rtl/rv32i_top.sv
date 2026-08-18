`timescale 1ns / 1ps

module rv32i_top (
    input clk,
    input rst
);
    logic        data_we;
    logic [2:0]  data_funct3;
    logic [31:0] instr_addr, instr_data;
    logic [31:0] data_addr, data_wdata, data_rdata;

    instruction_mem U_INSTRUCTION_MEM (.*);
    rv32i_cpu U_RV32I_CPU (
        .*,
        .data_funct3(data_funct3)
    );
    data_mem U_DATA_MEM (
        .*,
        .i_funct3(data_funct3)
    );
endmodule
