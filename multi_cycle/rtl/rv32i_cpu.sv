`timescale 1ns / 1ps
`include "define.vh"

module rv32i_cpu (
    input         clk,
    input         rst,
    output [31:0] instr_addr,
    input  [31:0] data_rdata,
    input  [31:0] instr_data,
    output        data_we,
    output [31:0] data_addr,
    output [2:0]  data_funct3,
    output [31:0] data_wdata
);
    logic        ir_we;
    logic        decode_we;
    logic        alu_out_we;
    logic        mdr_we;
    logic        reg_we;
    logic        pc_we;
    logic [1:0]  pc_src_sel;
    logic [1:0]  alu_src_a_sel;
    logic [1:0]  alu_src_b_sel;
    logic [1:0]  result_src_sel;
    logic [3:0]  alu_control;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [2:0]  memory_operation;
    logic [3:0]  alu_operation;
    logic        branch_taken;

    assign data_funct3 = memory_operation;

    control_unit U_CONTROL_UNIT (
        .clk(clk),
        .rst(rst),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .alu_operation(alu_operation),
        .branch_taken(branch_taken),
        .ir_we(ir_we),
        .decode_we(decode_we),
        .alu_out_we(alu_out_we),
        .mdr_we(mdr_we),
        .reg_we(reg_we),
        .pc_we(pc_we),
        .data_we(data_we),
        .pc_src_sel(pc_src_sel),
        .alu_src_a_sel(alu_src_a_sel),
        .alu_src_b_sel(alu_src_b_sel),
        .result_src_sel(result_src_sel),
        .alu_control(alu_control)
    );

    rv32i_datapath U_DATAPATH (
        .clk(clk),
        .rst(rst),
        .ir_we(ir_we),
        .decode_we(decode_we),
        .alu_out_we(alu_out_we),
        .mdr_we(mdr_we),
        .reg_we(reg_we),
        .pc_we(pc_we),
        .pc_src_sel(pc_src_sel),
        .alu_src_a_sel(alu_src_a_sel),
        .alu_src_b_sel(alu_src_b_sel),
        .result_src_sel(result_src_sel),
        .alu_control(alu_control),
        .instr_data(instr_data),
        .data_rdata(data_rdata),
        .instr_addr(instr_addr),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .memory_operation(memory_operation),
        .alu_operation(alu_operation),
        .branch_taken(branch_taken)
    );
endmodule
module control_unit (
    input              clk,
    input              rst,
    input        [6:0] opcode,
    input        [2:0] funct3,
    input        [6:0] funct7,
    input        [3:0] alu_operation,
    input              branch_taken,
    output logic       ir_we,
    output logic       decode_we,
    output logic       alu_out_we,
    output logic       mdr_we,
    output logic       reg_we,
    output logic       pc_we,
    output logic       data_we,
    output logic [1:0] pc_src_sel,
    output logic [1:0] alu_src_a_sel,
    output logic [1:0] alu_src_b_sel,
    output logic [1:0] result_src_sel,
    output logic [3:0] alu_control
);
    typedef enum logic [3:0] {
        FETCH       = 4'd0,
        DECODE      = 4'd1,
        R_EXEC      = 4'd2,
        I_EXEC      = 4'd3,
        AUIPC_EXEC  = 4'd4,
        ALU_WB      = 4'd5,
        LOAD_ADDR   = 4'd6,
        LOAD_READ   = 4'd7,
        LOAD_WB     = 4'd8,
        STORE_ADDR  = 4'd9,
        STORE_WRITE = 4'd10,
        BRANCH      = 4'd11,
        LUI_WB      = 4'd12,
        JUMP        = 4'd13,
        JALR_EXEC   = 4'd14
    } state_e;

    state_e state_q;
    state_e state_d;
    logic   instr_legal;

    always_comb begin
        instr_legal = 1'b0;
        unique case (opcode)
            `R_TYPE: begin
                unique case (funct3)
                    3'b000, 3'b101:
                        instr_legal = (funct7 == 7'b0000000) ||
                                      (funct7 == 7'b0100000);
                    3'b001, 3'b010, 3'b011, 3'b100, 3'b110, 3'b111:
                        instr_legal = (funct7 == 7'b0000000);
                    default:
                        instr_legal = 1'b0;
                endcase
            end
            `I_ALU_TYPE: begin
                unique case (funct3)
                    3'b001:
                        instr_legal = (funct7 == 7'b0000000);
                    3'b101:
                        instr_legal = (funct7 == 7'b0000000) ||
                                      (funct7 == 7'b0100000);
                    3'b000, 3'b010, 3'b011, 3'b100, 3'b110, 3'b111:
                        instr_legal = 1'b1;
                    default:
                        instr_legal = 1'b0;
                endcase
            end
            `LOAD_TYPE:
                instr_legal = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                              (funct3 == 3'b010) || (funct3 == 3'b100) ||
                              (funct3 == 3'b101);
            `S_TYPE:
                instr_legal = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                              (funct3 == 3'b010);
            `B_TYPE:
                instr_legal = (funct3 == `BEQ)  || (funct3 == `BNE) ||
                              (funct3 == `BLT)  || (funct3 == `BGE) ||
                              (funct3 == `BLTU) || (funct3 == `BGEU);
            `JALR_TYPE:
                instr_legal = (funct3 == 3'b000);
            `LUI_TYPE, `AUIPC_TYPE, `JAL_TYPE:
                instr_legal = 1'b1;
            default:
                instr_legal = 1'b0;
        endcase
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst)
            state_q <= FETCH;
        else
            state_q <= state_d;
    end

    always_comb begin
        state_d = FETCH;
        unique case (state_q)
            FETCH:  state_d = DECODE;
            DECODE: begin
                if (instr_legal) begin
                    unique case (opcode)
                        `R_TYPE:     state_d = R_EXEC;
                        `I_ALU_TYPE: state_d = I_EXEC;
                        `AUIPC_TYPE: state_d = AUIPC_EXEC;
                        `LOAD_TYPE:  state_d = LOAD_ADDR;
                        `S_TYPE:     state_d = STORE_ADDR;
                        `B_TYPE:     state_d = BRANCH;
                        `LUI_TYPE:   state_d = LUI_WB;
                        `JAL_TYPE:   state_d = JUMP;
                        `JALR_TYPE:  state_d = JALR_EXEC;
                        default:     state_d = FETCH;
                    endcase
                end
            end
            R_EXEC, I_EXEC, AUIPC_EXEC: state_d = ALU_WB;
            LOAD_ADDR:                   state_d = LOAD_READ;
            LOAD_READ:                   state_d = LOAD_WB;
            STORE_ADDR:                  state_d = STORE_WRITE;
            default:                     state_d = FETCH;
        endcase
    end

    always_comb begin
        ir_we          = 1'b0;
        decode_we      = 1'b0;
        alu_out_we     = 1'b0;
        mdr_we         = 1'b0;
        reg_we         = 1'b0;
        pc_we          = 1'b0;
        data_we        = 1'b0;
        pc_src_sel     = `PC_SRC_ALU;
        alu_src_a_sel  = `ALU_A_PC;
        alu_src_b_sel  = `ALU_B_REG_B;
        result_src_sel = `RESULT_ALU_OUT;
        alu_control    = `ADD;

        unique case (state_q)
            FETCH: begin
                ir_we         = 1'b1;
                pc_we         = 1'b1;
                alu_src_a_sel = `ALU_A_PC;
                alu_src_b_sel = `ALU_B_FOUR;
                alu_control   = `ADD;
            end

            DECODE: begin
                decode_we = instr_legal;
            end

            R_EXEC: begin
                alu_out_we    = 1'b1;
                alu_src_a_sel = `ALU_A_REG_A;
                alu_src_b_sel = `ALU_B_REG_B;
                alu_control   = alu_operation;
            end

            I_EXEC: begin
                alu_out_we    = 1'b1;
                alu_src_a_sel = `ALU_A_REG_A;
                alu_src_b_sel = `ALU_B_IMM;
                alu_control   = alu_operation;
            end

            AUIPC_EXEC: begin
                alu_out_we    = 1'b1;
                alu_src_a_sel = `ALU_A_OLD_PC;
                alu_src_b_sel = `ALU_B_IMM;
                alu_control   = `ADD;
            end

            ALU_WB: begin
                reg_we         = 1'b1;
                result_src_sel = `RESULT_ALU_OUT;
            end

            LOAD_ADDR, STORE_ADDR: begin
                alu_out_we    = 1'b1;
                alu_src_a_sel = `ALU_A_REG_A;
                alu_src_b_sel = `ALU_B_IMM;
                alu_control   = `ADD;
            end

            LOAD_READ: begin
                mdr_we = 1'b1;
            end

            LOAD_WB: begin
                reg_we         = 1'b1;
                result_src_sel = `RESULT_MDR;
            end

            STORE_WRITE: begin
                data_we = 1'b1;
            end

            BRANCH: begin
                alu_src_a_sel = `ALU_A_OLD_PC;
                alu_src_b_sel = `ALU_B_IMM;
                alu_control   = `ADD;
                pc_src_sel    = `PC_SRC_ALU;
                pc_we         = branch_taken;
            end

            LUI_WB: begin
                reg_we         = 1'b1;
                result_src_sel = `RESULT_IMM;
            end

            JUMP: begin
                reg_we         = 1'b1;
                result_src_sel = `RESULT_PC;
                alu_src_a_sel  = `ALU_A_OLD_PC;
                alu_src_b_sel  = `ALU_B_IMM;
                alu_control    = `ADD;
                pc_src_sel     = `PC_SRC_ALU;
                pc_we          = 1'b1;
            end

            JALR_EXEC: begin
                reg_we         = 1'b1;
                result_src_sel = `RESULT_PC;
                alu_src_a_sel  = `ALU_A_REG_A;
                alu_src_b_sel  = `ALU_B_IMM;
                alu_control    = `ADD;
                pc_src_sel     = `PC_SRC_JALR;
                pc_we          = 1'b1;
            end

            default: begin
            end
        endcase
    end
endmodule
