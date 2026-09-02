`timescale 1ns / 1ps
`include "define.vh"

module rv32i_datapath (
    input               clk,
    input               rst,
    input               ir_we,
    input               decode_we,
    input               alu_out_we,
    input               mdr_we,
    input               reg_we,
    input               pc_we,
    input        [ 1:0] pc_src_sel,
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
    output logic [ 2:0] memory_operation,
    output logic [ 3:0] alu_operation,
    output              branch_taken
);
    logic [31:0] pc;
    logic [31:0] old_pc;
    logic [31:0] ir;
    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] immediate;
    logic [ 4:0] destination;
    logic [ 2:0] branch_operation;
    logic [31:0] alu_out;
    logic [31:0] mdr;

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] decoded_immediate;
    logic [ 3:0] decoded_alu_operation;
    logic [31:0] alu_src_a;
    logic [31:0] alu_src_b;
    logic [31:0] alu_result;
    logic [31:0] reg_write_data;

    assign instr_addr = pc;
    assign data_addr  = alu_out;
    assign data_wdata = b;
    assign opcode     = ir[6:0];
    assign funct3     = ir[14:12];
    assign funct7     = ir[31:25];

    register_file U_REG_FILE (
        .clk(clk),
        .rst(rst),
        .read_addr1(ir[19:15]),
        .read_addr2(ir[24:20]),
        .write_addr(destination),
        .reg_we(reg_we),
        .write_data(reg_write_data),
        .read_data1(rs1_data),
        .read_data2(rs2_data)
    );

    imm_extender U_IMM_EXTENDER (
        .instr_data(ir),
        .imm_data(decoded_immediate)
    );

    always_comb begin
        decoded_alu_operation = `ADD;
        unique case (opcode)
            `R_TYPE:
                decoded_alu_operation = {ir[30], funct3};
            `I_ALU_TYPE: begin
                if ((funct3 == 3'b001) || (funct3 == 3'b101))
                    decoded_alu_operation = {ir[30], funct3};
                else
                    decoded_alu_operation = {1'b0, funct3};
            end
            default:
                decoded_alu_operation = `ADD;
        endcase
    end

    always_comb begin
        unique case (alu_src_a_sel)
            `ALU_A_PC:     alu_src_a = pc;
            `ALU_A_OLD_PC: alu_src_a = old_pc;
            `ALU_A_REG_A:  alu_src_a = a;
            default:       alu_src_a = 32'd0;
        endcase

        unique case (alu_src_b_sel)
            `ALU_B_REG_B:   alu_src_b = b;
            `ALU_B_IMM:     alu_src_b = immediate;
            `ALU_B_FOUR:    alu_src_b = 32'd4;
            default:        alu_src_b = 32'd0;
        endcase

        unique case (result_src_sel)
            `RESULT_ALU_OUT: reg_write_data = alu_out;
            `RESULT_MDR:     reg_write_data = mdr;
            `RESULT_IMM:     reg_write_data = immediate;
            `RESULT_PC:      reg_write_data = pc;
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
        .branch_control(branch_operation),
        .src_data1(a),
        .src_data2(b),
        .branch_taken(branch_taken)
    );

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            pc               <= 32'd0;
            old_pc           <= 32'd0;
            ir               <= 32'd0;
            a                <= 32'd0;
            b                <= 32'd0;
            immediate        <= 32'd0;
            destination      <= 5'd0;
            branch_operation <= 3'd0;
            memory_operation <= 3'd0;
            alu_operation    <= `ADD;
            alu_out          <= 32'd0;
            mdr              <= 32'd0;
        end else begin
            if (ir_we) begin
                ir     <= instr_data;
                old_pc <= pc;
            end
            if (decode_we) begin
                a                <= rs1_data;
                b                <= rs2_data;
                immediate        <= decoded_immediate;
                destination      <= ir[11:7];
                branch_operation <= funct3;
                memory_operation <= funct3;
                alu_operation    <= decoded_alu_operation;
            end
            if (alu_out_we)
                alu_out <= alu_result;
            if (mdr_we)
                mdr <= data_rdata;
            if (pc_we) begin
                unique case (pc_src_sel)
                    `PC_SRC_ALU:     pc <= alu_result;
                    `PC_SRC_JALR:    pc <= {alu_result[31:1], 1'b0};
                    default:         pc <= alu_result;
                endcase
            end
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
    // Keep the data array free of reset logic so Vivado can infer distributed
    // RAM.  valid preserves the previous architectural behavior: registers
    // that have not been written since reset read as zero.
    (* ram_style = "distributed" *) logic [31:0] reg_file [0:31];
    logic [31:0] valid;

    // FPGA configuration-time initialization is supported for distributed
    // RAM.  Runtime reset is handled by valid rather than clearing the RAM.
    initial begin
        for (int idx = 0; idx < 32; idx++)
            reg_file[idx] = 32'd0;
    end

    always_comb begin
        read_data1 = ((read_addr1 == 5'd0) || !valid[read_addr1]) ?
                     32'd0 : reg_file[read_addr1];
        read_data2 = ((read_addr2 == 5'd0) || !valid[read_addr2]) ?
                     32'd0 : reg_file[read_addr2];
    end

    always_ff @(posedge clk) begin
        if (reg_we && (write_addr != 5'd0))
            reg_file[write_addr] <= write_data;
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst)
            valid <= 32'd0;
        else if (reg_we && (write_addr != 5'd0))
            valid[write_addr] <= 1'b1;
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
