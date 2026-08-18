`ifndef RV32I_DEFINE_VH
`define RV32I_DEFINE_VH

// RV32I opcodes
`define LOAD_TYPE      7'b0000011
`define I_ALU_TYPE     7'b0010011
`define AUIPC_TYPE     7'b0010111
`define S_TYPE         7'b0100011
`define R_TYPE         7'b0110011
`define LUI_TYPE       7'b0110111
`define B_TYPE         7'b1100011
`define JALR_TYPE      7'b1100111
`define JAL_TYPE       7'b1101111

// ALU control: {instruction bit 30, funct3} for R/shift-immediate forms.
`define ADD            4'b0000
`define SUB            4'b1000
`define SLL            4'b0001
`define SLT            4'b0010
`define SLTU           4'b0011
`define XOR            4'b0100
`define SRL            4'b0101
`define SRA            4'b1101
`define OR             4'b0110
`define AND            4'b0111

// Branch funct3 values
`define BEQ            3'b000
`define BNE            3'b001
`define BLT            3'b100
`define BGE            3'b101
`define BLTU           3'b110
`define BGEU           3'b111

// V1 mux values retained for source compatibility.
`define ALU_SRC1_RS1   1'b0
`define ALU_SRC1_PC    1'b1
`define WB_SRC_ALU     2'b00
`define WB_SRC_MEM     2'b01
`define WB_SRC_PC4     2'b10
`define WB_SRC_IMM     2'b11
`define PC_NEXT_PC4    2'b00
`define PC_NEXT_BRANCH 2'b01
`define PC_NEXT_JUMP   2'b10
`define PC_NEXT_RS1_IMM 2'b11

// V2 multi-cycle datapath mux values.
`define ALU_A_PC       2'b00
`define ALU_A_OLD_PC   2'b01
`define ALU_A_REG_A    2'b10
`define ALU_B_REG_B    2'b00
`define ALU_B_IMM      2'b01
`define ALU_B_FOUR     2'b10
`define RESULT_ALU_OUT 2'b00
`define RESULT_MDR     2'b01
`define RESULT_IMM     2'b10
`define RESULT_PC      2'b11
`define PC_SRC_ALU     1'b0
`define PC_SRC_JALR    1'b1

`endif
