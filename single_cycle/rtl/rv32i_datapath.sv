`timescale 1ns / 1ps
`include "define.vh"

module rv32i_datapath (
    input               clk,
    input               rst,
    input               reg_we,
    input               alu_src1_sel,
    input               alu_src2_sel,
    input        [ 3:0] alu_control,
    input        [31:0] instr_data,
    input        [31:0] data_rdata,
    input        [ 1:0] wb_src_sel,
    input               branch_valid,
    input        [ 2:0] branch_control,
    input        [ 1:0] pc_next_sel,
    output       [31:0] instr_addr,
    output logic [31:0] data_addr,
    output logic [31:0] data_wdata
);
    logic [31:0] rs1_data, rs2_data, imm_data;
    logic [31:0] alu_src1_data, alu_src2_data, alu_result;
    logic [31:0] reg_write_data;
    logic [31:0] pc_plus_4, pc_target_addr, pc_jalr_addr;
    logic        branch_taken;

    assign data_addr  = alu_result;
    assign data_wdata = rs2_data;

    program_counter U_PC (
        .clk(clk),
        .rst(rst),
        .pc_next_sel(pc_next_sel),
        .branch_taken(branch_taken),
        .pc_target_addr(pc_target_addr),
        .pc_jalr_addr(pc_jalr_addr),
        .pc_curr(instr_addr),
        .pc_plus_4(pc_plus_4)
    );

    register_file U_REG_FILE (
        .clk(clk),
        .rst(rst),
        .read_addr1(instr_data[19:15]),
        .read_addr2(instr_data[24:20]),
        .write_addr(instr_data[11:7]),
        .reg_we(reg_we),
        .write_data(reg_write_data),
        .read_data1(rs1_data),
        .read_data2(rs2_data)
    );

    imm_extender U_IMM_EXTENDER (
        .instr_data(instr_data),
        .imm_data(imm_data)
    );

    mux_2x1 U_MUX_ALU_SRC1 (
        .in0(rs1_data),
        .in1(instr_addr),
        .mux_sel(alu_src1_sel),
        .out_mux(alu_src1_data)
    );

    mux_2x1 U_MUX_ALU_SRC2 (
        .in0(rs2_data),
        .in1(imm_data),
        .mux_sel(alu_src2_sel),
        .out_mux(alu_src2_data)
    );

    alu U_ALU (
        .src_data1(alu_src1_data),
        .src_data2(alu_src2_data),
        .alu_control(alu_control),
        .alu_result(alu_result)
    );

    pc_adder U_PC_TARGET_ADDR (
        .add_src1(instr_addr),
        .add_src2(imm_data),
        .add_result(pc_target_addr)
    );

    pc_adder U_PC_JALR_ADDR (
        .add_src1(rs1_data),
        .add_src2(imm_data),
        .add_result(pc_jalr_addr)
    );

    mux_4x1 U_MUX_WB_SRC (
        .in0(alu_result),
        .in1(data_rdata),
        .in2(pc_plus_4),
        .in3(imm_data),
        .mux_sel(wb_src_sel),
        .out_mux(reg_write_data)
    );

    branch_compare U_BRANCH_COMPARE (
        .branch_valid(branch_valid),
        .branch_control(branch_control),
        .src_data1(rs1_data),
        .src_data2(rs2_data),
        .branch_taken(branch_taken)
    );
endmodule

module mux_2x1 (
    input        [31:0] in0,
    input        [31:0] in1,
    input               mux_sel,
    output logic [31:0] out_mux
);
    assign out_mux = mux_sel ? in1 : in0;
endmodule

module mux_4x1 (
    input        [31:0] in0,
    input        [31:0] in1,
    input        [31:0] in2,
    input        [31:0] in3,
    input        [ 1:0] mux_sel,
    output logic [31:0] out_mux
);
    always_comb begin
        case (mux_sel)
            2'b00: out_mux = in0;
            2'b01: out_mux = in1;
            2'b10: out_mux = in2;
            2'b11: out_mux = in3;
        endcase
    end
endmodule

module imm_extender (
    input        [31:0] instr_data,
    output logic [31:0] imm_data
);
    always_comb begin
        imm_data = 32'd0;
        case (instr_data[6:0])
            // S-type immediate
            `S_TYPE:     imm_data = {{20{instr_data[31]}}, instr_data[31:25], instr_data[11:7]};
            // B-type branch offset immediate
            `B_TYPE:     imm_data = {{19{instr_data[31]}}, instr_data[31], instr_data[7], instr_data[30:25], instr_data[11:8], 1'b0};
            // I-type load immediate
            `LOAD_TYPE:  imm_data = {{20{instr_data[31]}}, instr_data[31:20]};
            // I-type ALU immediate
            `I_ALU_TYPE: imm_data = {{20{instr_data[31]}}, instr_data[31:20]};
            // I-type jump register immediate
            `JALR_TYPE:  imm_data = {{20{instr_data[31]}}, instr_data[31:20]};
            // U-type upper immediate for LUI
            `LUI_TYPE:   imm_data = {instr_data[31:12], 12'b0};
            // U-type upper immediate for AUIPC
            `AUIPC_TYPE: imm_data = {instr_data[31:12], 12'b0};
            // J-type jump offset immediate
            `JAL_TYPE:   imm_data = {{11{instr_data[31]}}, instr_data[31], instr_data[19:12], instr_data[20], instr_data[30:21], 1'b0};
            default:     imm_data = 32'd0;
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
    logic [31:0] reg_file[0:31];

// `ifdef SIMULATION
//     initial begin
//         reg_file[0] = 32'd0;
//         for (int idx = 1; idx < 32; idx = idx + 1) begin
//             reg_file[idx] = idx;
//         end
//     end
// `endif

    always_comb begin
        read_data1 = reg_file[read_addr1];
        read_data2 = reg_file[read_addr2];
        if (read_addr1 == 5'd0) read_data1 = 32'd0;
        if (read_addr2 == 5'd0) read_data2 = 32'd0;
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int idx = 0; idx < 32; idx = idx + 1) begin
                reg_file[idx] <= 32'd0;
            end
        end else begin
            reg_file[0] <= 32'd0;
            if (reg_we && (write_addr != 5'd0)) begin
                reg_file[write_addr] <= write_data;
            end
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
        case (alu_control)
            // ADD
            `ADD:  alu_result = src_data1 + src_data2;
            // SUB
            `SUB:  alu_result = src_data1 - src_data2;
            // SLL
            `SLL:  alu_result = src_data1 << src_data2[4:0];
            // SLT
            `SLT:  alu_result = ($signed(src_data1) < $signed(src_data2)) ? 32'd1 : 32'd0;
            // SLTU
            `SLTU: alu_result = (src_data1 < src_data2) ? 32'd1 : 32'd0;
            // XOR
            `XOR:  alu_result = src_data1 ^ src_data2;
            // SRL
            `SRL:  alu_result = src_data1 >> src_data2[4:0];
            // SRA
            `SRA:  alu_result = $signed(src_data1) >>> src_data2[4:0];
            // OR
            `OR:   alu_result = src_data1 | src_data2;
            // AND
            `AND:  alu_result = src_data1 & src_data2;
            default: alu_result = 32'd0;
        endcase
    end
endmodule

module program_counter (
    input               clk,
    input               rst,
    input        [ 1:0] pc_next_sel,
    input               branch_taken,
    input        [31:0] pc_target_addr,
    input        [31:0] pc_jalr_addr,
    output logic [31:0] pc_curr,
    output logic [31:0] pc_plus_4
);
    logic [31:0] pc_next;

    pc_adder U_PC_PLUS_4 (
        .add_src1(32'd4),
        .add_src2(pc_curr),
        .add_result(pc_plus_4)
    );

    always_comb begin
        case (pc_next_sel)
            // Next PC from taken branch target, otherwise fall through
            `PC_NEXT_BRANCH:  pc_next = branch_taken ? pc_target_addr : pc_plus_4;
            // Next PC from unconditional JAL target
            `PC_NEXT_JUMP:    pc_next = pc_target_addr;
            // Next PC from JALR target
            `PC_NEXT_RS1_IMM: pc_next = {pc_jalr_addr[31:1], 1'b0};
            // Default sequential next PC
            default:          pc_next = pc_plus_4;
        endcase
    end

    state_register U_PC_REG (
        .clk(clk),
        .rst(rst),
        .reg_next(pc_next),
        .reg_curr(pc_curr)
    );
endmodule

module pc_adder (
    input  [31:0] add_src1,
    input  [31:0] add_src2,
    output [31:0] add_result
);
    assign add_result = add_src1 + add_src2;
endmodule

module state_register (
    input         clk,
    input         rst,
    input  [31:0] reg_next,
    output [31:0] reg_curr
);
    logic [31:0] reg_q;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            reg_q <= 32'd0;
        end else begin
            reg_q <= reg_next;
        end
    end

    assign reg_curr = reg_q;
endmodule

module branch_compare (
    input               branch_valid,
    input        [ 2:0] branch_control,
    input        [31:0] src_data1,
    input        [31:0] src_data2,
    output logic        branch_taken
);
    always_comb begin
        branch_taken = 1'b0;
        if (branch_valid) begin
            case (branch_control)
                // BEQ
                `BEQ:  branch_taken = (src_data1 == src_data2);
                // BNE
                `BNE:  branch_taken = (src_data1 != src_data2);
                // BLT
                `BLT:  branch_taken = ($signed(src_data1) < $signed(src_data2));
                // BGE
                `BGE:  branch_taken = ($signed(src_data1) >= $signed(src_data2));
                // BLTU
                `BLTU: branch_taken = (src_data1 < src_data2);
                // BGEU
                `BGEU: branch_taken = (src_data1 >= src_data2);
                default: branch_taken = 1'b0;
            endcase
        end
    end
endmodule
