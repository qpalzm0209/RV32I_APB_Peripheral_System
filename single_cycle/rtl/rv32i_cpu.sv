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

    logic        reg_we, alu_src2_sel, branch_valid;
    logic        alu_src1_sel;
    logic [1:0]  wb_src_sel, pc_next_sel;
    logic [3:0]  alu_control;
    logic [2:0]  branch_control;

    control_unit U_CONTROL_UNIT (
        .funct7(instr_data[31:25]),
        .funct3(instr_data[14:12]),
        .opcode(instr_data[6:0]),
        .reg_we(reg_we),
        .alu_src1_sel(alu_src1_sel),
        .alu_src2_sel(alu_src2_sel),
        .alu_control(alu_control),
        .wb_src_sel(wb_src_sel),
        .data_funct3(data_funct3),
        .data_we(data_we),
        .branch_control(branch_control),
        .branch_valid(branch_valid),
        .pc_next_sel(pc_next_sel)
    );

    rv32i_datapath U_DATAPATH (
        .clk(clk),
        .rst(rst),
        .reg_we(reg_we),
        .alu_src1_sel(alu_src1_sel),
        .alu_src2_sel(alu_src2_sel),
        .alu_control(alu_control),
        .instr_data(instr_data),
        .data_rdata(data_rdata),
        .wb_src_sel(wb_src_sel),
        .branch_valid(branch_valid),
        .branch_control(branch_control),
        .pc_next_sel(pc_next_sel),
        .instr_addr(instr_addr),
        .data_addr(data_addr),
        .data_wdata(data_wdata)
    );
endmodule

module control_unit (
    input        [6:0] funct7,
    input        [2:0] funct3,
    input        [6:0] opcode,
    output logic       reg_we,
    output logic       alu_src1_sel,
    output logic       alu_src2_sel,
    output logic [3:0] alu_control,
    output logic [1:0] wb_src_sel,
    output logic [2:0] data_funct3,
    output logic       data_we,
    output logic [2:0] branch_control,
    output logic       branch_valid,
    output logic [1:0] pc_next_sel
);
    typedef enum logic [5:0] {
        UNKNOWN = 6'd0,
        ADD     = 6'd1,
        SUB     = 6'd2,
        SLL     = 6'd3,
        SLT     = 6'd4,
        SLTU    = 6'd5,
        XOR     = 6'd6,
        SRL     = 6'd7,
        SRA     = 6'd8,
        OR      = 6'd9,
        AND     = 6'd10,
        ADDI    = 6'd11,
        SLTI    = 6'd12,
        SLTIU   = 6'd13,
        XORI    = 6'd14,
        ORI     = 6'd15,
        ANDI    = 6'd16,
        SLLI    = 6'd17,
        SRLI    = 6'd18,
        SRAI    = 6'd19,
        LB      = 6'd20,
        LH      = 6'd21,
        LW      = 6'd22,
        LBU     = 6'd23,
        LHU     = 6'd24,
        SB      = 6'd25,
        SH      = 6'd26,
        SW      = 6'd27,
        BEQ     = 6'd28,
        BNE     = 6'd29,
        BLT     = 6'd30,
        BGE     = 6'd31,
        BLTU    = 6'd32,
        BGEU    = 6'd33,
        LUI     = 6'd34,
        AUIPC   = 6'd35,
        JAL     = 6'd36,
        JALR    = 6'd37
    } instr_kind_e;

    // Simulation-friendly decoded instruction kind for waveform inspection.
    instr_kind_e decoded_instr_kind;

    always_comb begin
        reg_we         = 1'b0;
        alu_src1_sel   = `ALU_SRC1_RS1;
        alu_src2_sel   = 1'b0;
        alu_control    = `ADD;
        wb_src_sel     = `WB_SRC_ALU;
        data_funct3    = 3'b000;
        data_we        = 1'b0;
        branch_control = 3'b000;
        branch_valid   = 1'b0;
        pc_next_sel    = `PC_NEXT_PC4;
        decoded_instr_kind = UNKNOWN;

        unique case (opcode)
            // R-type ALU: ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
            `R_TYPE: begin
                reg_we       = 1'b1;
                alu_src1_sel = `ALU_SRC1_RS1;
                alu_src2_sel = 1'b0;
                alu_control  = {funct7[5], funct3};
                unique case ({funct7[5], funct3})
                    `ADD:  decoded_instr_kind = ADD;
                    `SUB:  decoded_instr_kind = SUB;
                    `SLL:  decoded_instr_kind = SLL;
                    `SLT:  decoded_instr_kind = SLT;
                    `SLTU: decoded_instr_kind = SLTU;
                    `XOR:  decoded_instr_kind = XOR;
                    `SRL:  decoded_instr_kind = SRL;
                    `SRA:  decoded_instr_kind = SRA;
                    `OR:   decoded_instr_kind = OR;
                    `AND:  decoded_instr_kind = AND;
                    default: decoded_instr_kind = UNKNOWN;
                endcase
            end
            // S-type store: SB/SH/SW
            `S_TYPE: begin
                alu_src1_sel = `ALU_SRC1_RS1;
                alu_src2_sel = 1'b1;
                alu_control  = `ADD;
                data_funct3  = funct3;
                data_we      = 1'b1;
                unique case (funct3)
                    3'b000: decoded_instr_kind = SB;
                    3'b001: decoded_instr_kind = SH;
                    3'b010: decoded_instr_kind = SW;
                    default: decoded_instr_kind = UNKNOWN;
                endcase
            end
            // I-type load: LB/LH/LW/LBU/LHU
            `LOAD_TYPE: begin
                reg_we       = 1'b1;
                alu_src1_sel = `ALU_SRC1_RS1;
                alu_src2_sel = 1'b1;
                alu_control  = `ADD;
                wb_src_sel   = `WB_SRC_MEM;
                data_funct3  = funct3;
                unique case (funct3)
                    3'b000: decoded_instr_kind = LB;
                    3'b001: decoded_instr_kind = LH;
                    3'b010: decoded_instr_kind = LW;
                    3'b100: decoded_instr_kind = LBU;
                    3'b101: decoded_instr_kind = LHU;
                    default: decoded_instr_kind = UNKNOWN;
                endcase
            end
            // I-type ALU immediate: ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
            `I_ALU_TYPE: begin
                reg_we       = 1'b1;
                alu_src1_sel = `ALU_SRC1_RS1;
                alu_src2_sel = 1'b1;
                if ((funct3 == 3'b001) || (funct3 == 3'b101))
                    alu_control = {funct7[5], funct3};
                else
                    alu_control = {1'b0, funct3};
                unique case (funct3)
                    3'b000: decoded_instr_kind = ADDI;
                    3'b010: decoded_instr_kind = SLTI;
                    3'b011: decoded_instr_kind = SLTIU;
                    3'b100: decoded_instr_kind = XORI;
                    3'b110: decoded_instr_kind = ORI;
                    3'b111: decoded_instr_kind = ANDI;
                    3'b001: decoded_instr_kind = SLLI;
                    3'b101: decoded_instr_kind = funct7[5] ? SRAI : SRLI;
                    default: decoded_instr_kind = UNKNOWN;
                endcase
            end
            // B-type branch: BEQ/BNE/BLT/BGE/BLTU/BGEU
            `B_TYPE: begin
                branch_valid   = 1'b1;
                branch_control = funct3;
                pc_next_sel    = `PC_NEXT_BRANCH;
                unique case (funct3)
                    `BEQ:  decoded_instr_kind = BEQ;
                    `BNE:  decoded_instr_kind = BNE;
                    `BLT:  decoded_instr_kind = BLT;
                    `BGE:  decoded_instr_kind = BGE;
                    `BLTU: decoded_instr_kind = BLTU;
                    `BGEU: decoded_instr_kind = BGEU;
                    default: decoded_instr_kind = UNKNOWN;
                endcase
            end
            // U-type upper immediate: LUI
            `LUI_TYPE: begin
                reg_we       = 1'b1;
                wb_src_sel   = `WB_SRC_IMM;
                decoded_instr_kind = LUI;
            end
            // U-type upper immediate plus PC: AUIPC
            `AUIPC_TYPE: begin
                reg_we       = 1'b1;
                alu_src1_sel = `ALU_SRC1_PC;
                alu_src2_sel = 1'b1;
                alu_control  = `ADD;
                wb_src_sel   = `WB_SRC_ALU;
                decoded_instr_kind = AUIPC;
            end
            // J-type jump and link: JAL
            `JAL_TYPE: begin
                reg_we      = 1'b1;
                wb_src_sel  = `WB_SRC_PC4;
                pc_next_sel = `PC_NEXT_JUMP;
                decoded_instr_kind = JAL;
            end
            // I-type jump and link register: JALR
            `JALR_TYPE: begin
                reg_we      = 1'b1;
                wb_src_sel  = `WB_SRC_PC4;
                pc_next_sel = `PC_NEXT_RS1_IMM;
                decoded_instr_kind = JALR;
            end
            default: begin
            end
        endcase
    end
endmodule
