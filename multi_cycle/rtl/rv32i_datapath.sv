`timescale 1ns / 1ps
`include "define.vh"

module rv32i_datapath (
    input               clk,
    input               rst,
    input               ir_we,
    input               operand_we,
    input               alu_out_we,
    input               mdr_we,
    input               reg_we,
    input               pc_we,
    input               pc_src_sel,
    input        [ 1:0] alu_src_a_sel,
    input        [ 1:0] alu_src_b_sel,
    input        [ 1:0] result_src_sel,
    input        [ 3:0] alu_control,
    input        [31:0] instr_data,
    input        [31:0] data_rdata,
    output       [31:0] instr_addr,
    output       [31:0] data_addr,
    output       [31:0] data_wdata,
    output       [ 6:0] opcode,
    output       [ 2:0] funct3,
    output       [ 6:0] funct7,
    output              branch_taken
);
    logic [31:0] pc_q;
    logic [31:0] old_pc_q;
    logic [31:0] ir_q;
    logic [31:0] reg_a_q;
    logic [31:0] reg_b_q;
    logic [31:0] alu_out_q;
    logic [31:0] mdr_q;

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm_data;
    logic [31:0] alu_src_a;
    logic [31:0] alu_src_b;
    logic [31:0] alu_result;
    logic [31:0] reg_write_data;

    assign instr_addr = pc_q;
    assign data_addr  = alu_out_q;
    assign data_wdata = reg_b_q;
    assign opcode     = ir_q[6:0];
    assign funct3     = ir_q[14:12];
    assign funct7     = ir_q[31:25];

    register_file U_REG_FILE (
        .clk(clk),
        .rst(rst),
        .read_addr1(ir_q[19:15]),
        .read_addr2(ir_q[24:20]),
        .write_addr(ir_q[11:7]),
        .reg_we(reg_we),
        .write_data(reg_write_data),
        .read_data1(rs1_data),
        .read_data2(rs2_data)
    );

    imm_extender U_IMM_EXTENDER (
        .instr_data(ir_q),
        .imm_data(imm_data)
    );

    always_comb begin
        unique case (alu_src_a_sel)
            `ALU_A_PC:     alu_src_a = pc_q;
            `ALU_A_OLD_PC: alu_src_a = old_pc_q;
            `ALU_A_REG_A:  alu_src_a = reg_a_q;
            default:       alu_src_a = 32'd0;
        endcase

        unique case (alu_src_b_sel)
            `ALU_B_REG_B: alu_src_b = reg_b_q;
            `ALU_B_IMM:   alu_src_b = imm_data;
            `ALU_B_FOUR:  alu_src_b = 32'd4;
            default:      alu_src_b = 32'd0;
        endcase

        unique case (result_src_sel)
            `RESULT_ALU_OUT: reg_write_data = alu_out_q;
            `RESULT_MDR:     reg_write_data = mdr_q;
            `RESULT_IMM:     reg_write_data = imm_data;
            `RESULT_PC:      reg_write_data = pc_q;
            default:         reg_write_data = 32'd0;
        endcase
    end

    alu U_ALU (
        .src_data1(alu_src_a),
        .src_data2(alu_src_b),
        .alu_control(alu_control),
        .alu_result(alu_result)
    );

    branch_compare U_BRANCH_COMPARE (
        .branch_control(funct3),
        .src_data1(reg_a_q),
        .src_data2(reg_b_q),
        .branch_taken(branch_taken)
    );

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            pc_q      <= 32'd0;
            old_pc_q  <= 32'd0;
            ir_q      <= 32'd0;
            reg_a_q   <= 32'd0;
            reg_b_q   <= 32'd0;
            alu_out_q <= 32'd0;
            mdr_q     <= 32'd0;
        end else begin
            if (ir_we) begin
                ir_q     <= instr_data;
                old_pc_q <= pc_q;
            end
            if (operand_we) begin
                reg_a_q <= rs1_data;
                reg_b_q <= rs2_data;
            end
            if (alu_out_we)
                alu_out_q <= alu_result;
            if (mdr_we)
                mdr_q <= data_rdata;
            if (pc_we)
                pc_q <= pc_src_sel ? {alu_result[31:1], 1'b0} : alu_result;
        end
    end
endmodule
module imm_extender (
    input        [31:0] instr_data,
    output logic [31:0] imm_data
);
    always_comb begin
        unique case (instr_data[6:0])
            `S_TYPE:
                imm_data = {{20{instr_data[31]}}, instr_data[31:25],
                            instr_data[11:7]};
            `B_TYPE:
                imm_data = {{19{instr_data[31]}}, instr_data[31],
                            instr_data[7], instr_data[30:25],
                            instr_data[11:8], 1'b0};
            `LOAD_TYPE, `I_ALU_TYPE, `JALR_TYPE:
                imm_data = {{20{instr_data[31]}}, instr_data[31:20]};
            `LUI_TYPE, `AUIPC_TYPE:
                imm_data = {instr_data[31:12], 12'b0};
            `JAL_TYPE:
                imm_data = {{11{instr_data[31]}}, instr_data[31],
                            instr_data[19:12], instr_data[20],
                            instr_data[30:21], 1'b0};
            default:
                imm_data = 32'd0;
        endcase
    end
endmodule
module register_file (
    input               clk,
    input               rst,
    input        [ 4:0] read_addr1,
    input        [ 4:0] read_addr2,
    input        [ 4:0] write_addr,
    input               reg_we,
    input        [31:0] write_data,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2
);
    logic [31:0] reg_file [0:31];

    always_comb begin
        read_data1 = (read_addr1 == 5'd0) ? 32'd0 : reg_file[read_addr1];
        read_data2 = (read_addr2 == 5'd0) ? 32'd0 : reg_file[read_addr2];
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int idx = 0; idx < 32; idx++)
                reg_file[idx] <= 32'd0;
        end else begin
            reg_file[0] <= 32'd0;
            if (reg_we && (write_addr != 5'd0))
                reg_file[write_addr] <= write_data;
        end
    end
endmodule

module alu (
    input        [31:0] src_data1,
    input        [31:0] src_data2,
    input        [ 3:0] alu_control,
    output logic [31:0] alu_result
);
    always_comb begin
        unique case (alu_control)
            `ADD:  alu_result = src_data1 + src_data2;
            `SUB:  alu_result = src_data1 - src_data2;
            `SLL:  alu_result = src_data1 << src_data2[4:0];
            `SLT:  alu_result = ($signed(src_data1) < $signed(src_data2)) ? 32'd1 : 32'd0;
            `SLTU: alu_result = (src_data1 < src_data2) ? 32'd1 : 32'd0;
            `XOR:  alu_result = src_data1 ^ src_data2;
            `SRL:  alu_result = src_data1 >> src_data2[4:0];
            `SRA:  alu_result = $signed(src_data1) >>> src_data2[4:0];
            `OR:   alu_result = src_data1 | src_data2;
            `AND:  alu_result = src_data1 & src_data2;
            default: alu_result = 32'd0;
        endcase
    end
endmodule

module branch_compare (
    input        [ 2:0] branch_control,
    input        [31:0] src_data1,
    input        [31:0] src_data2,
    output logic        branch_taken
);
    always_comb begin
        unique case (branch_control)
            `BEQ:  branch_taken = (src_data1 == src_data2);
            `BNE:  branch_taken = (src_data1 != src_data2);
            `BLT:  branch_taken = ($signed(src_data1) < $signed(src_data2));
            `BGE:  branch_taken = ($signed(src_data1) >= $signed(src_data2));
            `BLTU: branch_taken = (src_data1 < src_data2);
            `BGEU: branch_taken = (src_data1 >= src_data2);
            default: branch_taken = 1'b0;
        endcase
    end
endmodule
