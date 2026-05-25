`timescale 1ns / 1ps
`include "define.vh"

module rv32i_datapath (
    input               clk,
    input               rst,
    input               fetch_reg_we,
    input               decode_reg_we,
    input               execute_reg_we,
    input               mem_reg_we,
    input               wb_result_we,
    input               pc_reg_we,
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
    output logic [31:0] data_wdata,
    output logic [ 6:0] instr_opcode,
    output logic [ 2:0] instr_funct3,
    output logic [ 6:0] instr_funct7
);
    logic [31:0] rs1_data, rs2_data, imm_data;
    logic [31:0] alu_src1_data, alu_src2_data, alu_result;
    logic [31:0] reg_write_data;
    logic [31:0] wb_capture_data;
    logic [31:0] wb_capture_rd;
    logic [31:0] pc_plus_4;
    logic        branch_taken;

    logic [31:0] ir_reg;
    logic [31:0] fetch_pc_reg;
    logic [31:0] fetch_pc4_reg;

    logic [31:0] decode_pc_reg;
    logic [31:0] decode_pc4_reg;
    logic [31:0] decode_imm_reg;
    logic [31:0] decode_rs1_reg;
    logic [31:0] decode_rs2_reg;
    logic [31:0] decode_rd_reg;

    logic [31:0] execute_alu_result_reg;
    logic [31:0] mem_read_data_reg;
    logic [31:0] wb_write_data_reg;
    logic [31:0] wb_rd_reg;

    assign instr_opcode = ir_reg[6:0];
    assign instr_funct3 = ir_reg[14:12];
    assign instr_funct7 = ir_reg[31:25];

    // For load/store, the ALU result becomes the external bus address.
    assign data_addr      = execute_alu_result_reg;
    // For store, rs2 is carried outward as the external write data.
    assign data_wdata     = decode_rs2_reg;
    assign reg_write_data = wb_write_data_reg;

    program_counter U_PC (
        .clk(clk),
        .rst(rst),
        .we(pc_reg_we),
        .pc_next_sel(pc_next_sel),
        .branch_taken(branch_taken),
        .pc_target_addr(execute_alu_result_reg),
        .pc_jalr_addr(execute_alu_result_reg),
        .pc_curr(instr_addr),
        .pc_plus_4(pc_plus_4)
    );

    // ==================== FETCH ====================
    sl_register U_IR_REG (
        .clk(clk),
        .rst(rst),
        .we(fetch_reg_we),
        .write_data(instr_data),
        .read_data(ir_reg)
    );

    sl_register U_FETCH_PC_REG (
        .clk(clk),
        .rst(rst),
        .we(fetch_reg_we),
        .write_data(instr_addr),
        .read_data(fetch_pc_reg)
    );

    sl_register U_FETCH_PC4_REG (
        .clk(clk),
        .rst(rst),
        .we(fetch_reg_we),
        .write_data(pc_plus_4),
        .read_data(fetch_pc4_reg)
    );

    // ==================== DECODE ====================
    register_file U_REG_FILE (
        .clk(clk),
        .rst(rst),
        .read_addr1(ir_reg[19:15]),
        .read_addr2(ir_reg[24:20]),
        .write_addr(wb_rd_reg[4:0]),
        .reg_we(reg_we),
        .write_data(reg_write_data),
        .read_data1(rs1_data),
        .read_data2(rs2_data)
    );

    imm_extender U_IMM_EXTENDER (
        .instr_data(ir_reg),
        .imm_data  (imm_data)
    );

    sl_register U_DECODE_PC_REG (
        .clk(clk),
        .rst(rst),
        .we(decode_reg_we),
        .write_data(fetch_pc_reg),
        .read_data(decode_pc_reg)
    );

    sl_register U_DECODE_PC4_REG (
        .clk(clk),
        .rst(rst),
        .we(decode_reg_we),
        .write_data(fetch_pc4_reg),
        .read_data(decode_pc4_reg)
    );

    sl_register U_DECODE_RS1_REG (
        .clk(clk),
        .rst(rst),
        .we(decode_reg_we),
        .write_data(rs1_data),
        .read_data(decode_rs1_reg)
    );

    sl_register U_DECODE_RS2_REG (
        .clk(clk),
        .rst(rst),
        .we(decode_reg_we),
        .write_data(rs2_data),
        .read_data(decode_rs2_reg)
    );

    sl_register U_DECODE_IMM_REG (
        .clk(clk),
        .rst(rst),
        .we(decode_reg_we),
        .write_data(imm_data),
        .read_data(decode_imm_reg)
    );

    sl_register U_DECODE_RD_REG (
        .clk(clk),
        .rst(rst),
        .we(decode_reg_we),
        .write_data({27'd0, ir_reg[11:7]}),
        .read_data(decode_rd_reg)
    );

    // ==================== EXECUTE ====================
    mux_2x1 U_MUX_ALU_SRC1 (
        .in0(decode_rs1_reg),
        .in1(decode_pc_reg),
        .mux_sel(alu_src1_sel),
        .out_mux(alu_src1_data)
    );

    mux_2x1 U_MUX_ALU_SRC2 (
        .in0(decode_rs2_reg),
        .in1(decode_imm_reg),
        .mux_sel(alu_src2_sel),
        .out_mux(alu_src2_data)
    );

    alu U_ALU (
        .src_data1  (alu_src1_data),
        .src_data2  (alu_src2_data),
        .alu_control(alu_control),
        .alu_result (alu_result)
    );

    sl_register U_EXECUTE_ALUOUT_REG (
        .clk(clk),
        .rst(rst),
        .we(execute_reg_we),
        .write_data(alu_result),
        .read_data(execute_alu_result_reg)
    );

    // ==================== MEMORY ====================
    sl_register U_MEM_RDATA_REG (
        .clk(clk),
        .rst(rst),
        .we(mem_reg_we),
        .write_data(data_rdata),
        .read_data(mem_read_data_reg)
    );

    // ==================== WRITE-BACK ====================
    // WB 단계는 "지금 고르는 값"을 바로 regfile에 쓰지 않고,
    // 한 번 WB 결과 레지스터에 저장한 뒤 다음 단계에서 기록한다.
    // 이렇게 하면 구조상 MEM/WB stage가 더 또렷해진다.
    always_comb begin
        wb_capture_rd = decode_rd_reg;
        case (wb_src_sel)
            `WB_SRC_ALU: wb_capture_data = alu_result;
            `WB_SRC_MEM: wb_capture_data = data_rdata;
            `WB_SRC_PC4: wb_capture_data = decode_pc4_reg;
            `WB_SRC_IMM: begin
                // LUI는 DECODE 단계에서 바로 WB 데이터가 확정되므로
                // decode_reg가 아직 갱신되기 전의 imm_data/rd를 사용한다.
                wb_capture_data = decode_reg_we ? imm_data : decode_imm_reg;
                wb_capture_rd   = decode_reg_we ? {27'd0, ir_reg[11:7]} : decode_rd_reg;
            end
            default: wb_capture_data = 32'd0;
        endcase
    end

    sl_register U_WB_WRITE_DATA_REG (
        .clk(clk),
        .rst(rst),
        .we(wb_result_we),
        .write_data(wb_capture_data),
        .read_data(wb_write_data_reg)
    );

    sl_register U_WB_RD_REG (
        .clk(clk),
        .rst(rst),
        .we(wb_result_we),
        .write_data(wb_capture_rd),
        .read_data(wb_rd_reg)
    );

    branch_compare U_BRANCH_COMPARE (
        .branch_valid(branch_valid),
        .branch_control(branch_control),
        .src_data1(decode_rs1_reg),
        .src_data2(decode_rs2_reg),
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
            `S_TYPE:
            imm_data = {
                {20{instr_data[31]}}, instr_data[31:25], instr_data[11:7]
            };
            `B_TYPE:
            imm_data = {
                {19{instr_data[31]}},
                instr_data[31],
                instr_data[7],
                instr_data[30:25],
                instr_data[11:8],
                1'b0
            };
            `LOAD_TYPE: imm_data = {{20{instr_data[31]}}, instr_data[31:20]};
            `I_ALU_TYPE: imm_data = {{20{instr_data[31]}}, instr_data[31:20]};
            `JALR_TYPE: imm_data = {{20{instr_data[31]}}, instr_data[31:20]};
            `LUI_TYPE: imm_data = {instr_data[31:12], 12'b0};
            `AUIPC_TYPE: imm_data = {instr_data[31:12], 12'b0};
            `JAL_TYPE:
            imm_data = {
                {11{instr_data[31]}},
                instr_data[31],
                instr_data[19:12],
                instr_data[20],
                instr_data[30:21],
                1'b0
            };
            default: imm_data = 32'd0;
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
            `ADD: alu_result = src_data1 + src_data2;
            `SUB: alu_result = src_data1 - src_data2;
            `SLL: alu_result = src_data1 << src_data2[4:0];
            `SLT:
            alu_result = ($signed(src_data1) < $signed(src_data2)) ? 32'd1 :
                32'd0;
            `SLTU: alu_result = (src_data1 < src_data2) ? 32'd1 : 32'd0;
            `XOR: alu_result = src_data1 ^ src_data2;
            `SRL: alu_result = src_data1 >> src_data2[4:0];
            `SRA: alu_result = $signed(src_data1) >>> src_data2[4:0];
            `OR: alu_result = src_data1 | src_data2;
            `AND: alu_result = src_data1 & src_data2;
            default: alu_result = 32'd0;
        endcase
    end
endmodule

module program_counter (
    input               clk,
    input               rst,
    input               we,
    input        [ 1:0] pc_next_sel,
    input               branch_taken,
    input        [31:0] pc_target_addr,
    input        [31:0] pc_jalr_addr,
    output logic [31:0] pc_curr,
    output logic [31:0] pc_plus_4
);
    logic [31:0] pc_next;

    pc_adder U_PC_PLUS_4 (
        .add_src1  (32'd4),
        .add_src2  (pc_curr),
        .add_result(pc_plus_4)
    );

    always_comb begin
        case (pc_next_sel)
            `PC_NEXT_BRANCH:
            pc_next = branch_taken ? pc_target_addr : pc_plus_4;
            `PC_NEXT_JUMP: pc_next = pc_target_addr;
            `PC_NEXT_RS1_IMM: pc_next = {pc_jalr_addr[31:1], 1'b0};
            default: pc_next = pc_plus_4;
        endcase
    end

    state_register U_PC_REG (
        .clk(clk),
        .rst(rst),
        .we(we),
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
    input         we,
    input  [31:0] reg_next,
    output [31:0] reg_curr
);
    logic [31:0] reg_q;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            reg_q <= 32'd0;
        end else if (we) begin
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
                `BEQ: branch_taken = (src_data1 == src_data2);
                `BNE: branch_taken = (src_data1 != src_data2);
                `BLT: branch_taken = ($signed(src_data1) < $signed(src_data2));
                `BGE: branch_taken = ($signed(src_data1) >= $signed(src_data2));
                `BLTU: branch_taken = (src_data1 < src_data2);
                `BGEU: branch_taken = (src_data1 >= src_data2);
                default: branch_taken = 1'b0;
            endcase
        end
    end
endmodule
