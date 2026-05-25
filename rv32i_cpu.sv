`timescale 1ns / 1ps
`include "define.vh"

module rv32i_cpu (
    input         clk,
    input         rst,
    // 명령어 버스
    // i_addr  : 예전 instr_addr
    // i_rdata : 예전 instr_data
    // i_valid : 버스형 구조에서 추가된 fetch 요청 신호
    output logic        i_valid,
    output logic [31:0] i_addr,
    input  logic [31:0] i_rdata,
    input  logic        i_ready,
    // 데이터 버스
    // d_addr  : 예전 data_addr
    // d_wdata : 예전 data_wdata
    // d_rdata : 예전 data_rdata
    // d_size  : 예전 data_funct3
    // d_write : 예전 data_we의 쓰기 의미
    // d_valid : 버스형 구조에서 추가된 데이터 요청 유효 신호
    output logic        d_valid,
    output logic        d_write,
    output logic [31:0] d_addr,
    // CPU 밖으로는 load/store의 원래 funct3 값을 그대로 내보낸다.
    // APB master와 연결할 때는 top에서 버스 의미에 맞는 이름(d_size)으로 다시 해석한다.
    output logic [ 2:0] d_funct3,
    output logic [31:0] d_wdata,
    input  logic [31:0] d_rdata,
    input  logic        d_ready
);
    // 공부하기 쉽게 stage enable은 다시 개별 신호로 분해해 둔다.
    logic        fetch_reg_we;
    logic        decode_reg_we;
    logic        execute_reg_we;
    logic        mem_reg_we;
    logic        wb_result_we;
    logic        pc_reg_we;
    logic        reg_we;
    logic        alu_src1_sel;
    logic        alu_src2_sel;
    logic        branch_valid;
    logic [1:0]  wb_src_sel;
    logic [1:0]  pc_next_sel;
    logic [3:0]  alu_control;
    logic [2:0]  data_funct3;
    logic [2:0]  branch_control;
    logic [6:0]  instr_opcode;
    logic [2:0]  instr_funct3;
    logic [6:0]  instr_funct7;

    // d_size는 현재 단계에서는 data_funct3와 같은 의미다.
    assign d_funct3 = data_funct3;

    control_unit U_CONTROL_UNIT (
        .clk(clk),
        .rst(rst),
        .i_ready(i_ready),
        .d_ready(d_ready),
        .opcode(instr_opcode),
        .funct3(instr_funct3),
        .funct7(instr_funct7),
        .fetch_reg_we(fetch_reg_we),
        .decode_reg_we(decode_reg_we),
        .execute_reg_we(execute_reg_we),
        .mem_reg_we(mem_reg_we),
        .wb_result_we(wb_result_we),
        .pc_reg_we(pc_reg_we),
        .reg_we(reg_we),
        .alu_src1_sel(alu_src1_sel),
        .alu_src2_sel(alu_src2_sel),
        .alu_control(alu_control),
        .wb_src_sel(wb_src_sel),
        .data_funct3(data_funct3),
        .d_write(d_write),
        .d_valid(d_valid),
        .i_valid(i_valid),
        .branch_control(branch_control),
        .branch_valid(branch_valid),
        .pc_next_sel(pc_next_sel)
    );

    rv32i_datapath U_DATAPATH (
        .clk(clk),
        .rst(rst),
        .fetch_reg_we(fetch_reg_we),
        .decode_reg_we(decode_reg_we),
        .execute_reg_we(execute_reg_we),
        .mem_reg_we(mem_reg_we),
        .wb_result_we(wb_result_we),
        .pc_reg_we(pc_reg_we),
        .reg_we(reg_we),
        .alu_src1_sel(alu_src1_sel),
        .alu_src2_sel(alu_src2_sel),
        .alu_control(alu_control),
        .instr_data(i_rdata),
        .data_rdata(d_rdata),
        .wb_src_sel(wb_src_sel),
        .branch_valid(branch_valid),
        .branch_control(branch_control),
        .pc_next_sel(pc_next_sel),
        .instr_addr(i_addr),
        .data_addr(d_addr),
        .data_wdata(d_wdata),
        .instr_opcode(instr_opcode),
        .instr_funct3(instr_funct3),
        .instr_funct7(instr_funct7)
    );
endmodule

module control_unit (
    input               clk,
    input               rst,
    input               i_ready,
    input               d_ready,
    input        [ 6:0] opcode,
    input        [ 2:0] funct3,
    input        [ 6:0] funct7,
    // 원형 포트 기준으로 분해된 stage enable
    output logic        fetch_reg_we,
    output logic        decode_reg_we,
    output logic        execute_reg_we,
    output logic        mem_reg_we,
    output logic        wb_result_we,
    output logic        pc_reg_we,
    output logic        reg_we,
    output logic        alu_src1_sel,
    output logic        alu_src2_sel,
    output logic [ 3:0] alu_control,
    output logic [ 1:0] wb_src_sel,
    output logic [ 2:0] data_funct3,
    // data_we 원형 포트는 버스형 구조에서 d_write로 이름을 바꿔 유지
    output logic        d_write,
    // 버스형 구조에서 추가된 요청 유효 신호
    output logic        d_valid,
    output logic        i_valid,
    output logic [ 2:0] branch_control,
    output logic        branch_valid,
    output logic [ 1:0] pc_next_sel
);
    typedef enum logic [3:0] {
        S_FETCH         = 4'd0,
        S_DECODE        = 4'd1,
        S_EX_ALU        = 4'd2,
        S_EX_ADDR       = 4'd3,
        S_EX_BRANCH     = 4'd4,
        S_BRANCH_COMMIT = 4'd5,
        S_EX_JUMP       = 4'd6,
        S_MEM_READ      = 4'd7,
        S_MEM_WRITE     = 4'd8,
        S_WB_ALU        = 4'd9,
        S_WB_LOAD       = 4'd10,
        S_WB_JUMP       = 4'd11,
        S_WB_LUI        = 4'd12
    } state_e;

    state_e state, next_state;

    // ------------------------------
    // DECODE 결과를 한 사이클 고정해두는 제어 레지스터
    // 목적:
    // 1) DECODE에서 한 번 해석한 제어 정보를 EXECUTE/MEM/WB에서 재사용
    // 2) IR -> 제어 decode -> ALU 로 바로 이어지는 조합 경로를 줄이기
    // ------------------------------
    logic [6:0] dec_opcode_reg;
    logic [2:0] dec_funct3_reg;
    logic       ex_alu_src1_sel_reg;
    logic       ex_alu_src2_sel_reg;
    logic [3:0] ex_alu_control_reg;

    logic       dec_alu_src1_sel_next;
    logic       dec_alu_src2_sel_next;
    logic [3:0] dec_alu_control_next;

    // 현재 IR 기준으로 "이번 명령어가 어떤 EX 제어를 써야 하는지" 계산한다.
    // 이 값은 DECODE 끝에서 레지스터에 저장되고,
    // 이후 EXECUTE 단계에서는 저장된 제어값만 사용한다.
    always_comb begin
        dec_alu_src1_sel_next = `ALU_SRC1_RS1;
        dec_alu_src2_sel_next = 1'b0;
        dec_alu_control_next  = `ADD;

        unique case (opcode)
            `AUIPC_TYPE: begin
                dec_alu_src1_sel_next = `ALU_SRC1_PC;
                dec_alu_src2_sel_next = 1'b1;
                dec_alu_control_next  = `ADD;
            end

            `I_ALU_TYPE: begin
                dec_alu_src1_sel_next = `ALU_SRC1_RS1;
                dec_alu_src2_sel_next = 1'b1;
                if ((funct3 == 3'b001) || (funct3 == 3'b101))
                    dec_alu_control_next = {funct7[5], funct3};
                else
                    dec_alu_control_next = {1'b0, funct3};
            end

            `R_TYPE: begin
                dec_alu_src1_sel_next = `ALU_SRC1_RS1;
                dec_alu_src2_sel_next = 1'b0;
                dec_alu_control_next  = {funct7[5], funct3};
            end

            `LOAD_TYPE,
            `S_TYPE: begin
                dec_alu_src1_sel_next = `ALU_SRC1_RS1;
                dec_alu_src2_sel_next = 1'b1;
                dec_alu_control_next  = `ADD;
            end

            `B_TYPE: begin
                dec_alu_src1_sel_next = `ALU_SRC1_PC;
                dec_alu_src2_sel_next = 1'b1;
                dec_alu_control_next  = `ADD;
            end

            `JAL_TYPE: begin
                dec_alu_src1_sel_next = `ALU_SRC1_PC;
                dec_alu_src2_sel_next = 1'b1;
                dec_alu_control_next  = `ADD;
            end

            `JALR_TYPE: begin
                dec_alu_src1_sel_next = `ALU_SRC1_RS1;
                dec_alu_src2_sel_next = 1'b1;
                dec_alu_control_next  = `ADD;
            end

            default: begin
                dec_alu_src1_sel_next = `ALU_SRC1_RS1;
                dec_alu_src2_sel_next = 1'b0;
                dec_alu_control_next  = `ADD;
            end
        endcase
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state               <= S_FETCH;
            dec_opcode_reg      <= 7'd0;
            dec_funct3_reg      <= 3'd0;
            ex_alu_src1_sel_reg <= `ALU_SRC1_RS1;
            ex_alu_src2_sel_reg <= 1'b0;
            ex_alu_control_reg  <= `ADD;
        end else begin
            state <= next_state;

            // DECODE 단계 끝에서 현재 명령어의 제어 정보를 저장한다.
            // 이후 EX/MEM/WB는 IR을 다시 직접 해석하지 않고 이 값을 사용한다.
            if (decode_reg_we) begin
                dec_opcode_reg      <= opcode;
                dec_funct3_reg      <= funct3;
                ex_alu_src1_sel_reg <= dec_alu_src1_sel_next;
                ex_alu_src2_sel_reg <= dec_alu_src2_sel_next;
                ex_alu_control_reg  <= dec_alu_control_next;
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            S_FETCH: begin
                if (i_ready)
                    next_state = S_DECODE;
            end
            S_DECODE: begin
                unique case (opcode)
                    `R_TYPE,
                    `I_ALU_TYPE,
                    `AUIPC_TYPE: next_state = S_EX_ALU;
                    `LOAD_TYPE,
                    `S_TYPE: next_state = S_EX_ADDR;
                    `B_TYPE: next_state = S_EX_BRANCH;
                    `JAL_TYPE,
                    `JALR_TYPE: next_state = S_EX_JUMP;
                    `LUI_TYPE: next_state = S_WB_LUI;
                    default: next_state = S_FETCH;
                endcase
            end
            S_EX_ALU: next_state = S_WB_ALU;
            S_EX_ADDR: begin
                if (dec_opcode_reg == `LOAD_TYPE)
                    next_state = S_MEM_READ;
                else
                    next_state = S_MEM_WRITE;
            end
            S_EX_BRANCH: next_state = S_BRANCH_COMMIT;
            S_BRANCH_COMMIT: next_state = S_FETCH;
            S_EX_JUMP: next_state = S_WB_JUMP;
            S_MEM_READ: begin
                if (d_ready)
                    next_state = S_WB_LOAD;
            end
            S_MEM_WRITE: begin
                if (d_ready)
                    next_state = S_FETCH;
            end
            S_WB_ALU: next_state = S_FETCH;
            S_WB_LOAD: next_state = S_FETCH;
            S_WB_JUMP: next_state = S_FETCH;
            S_WB_LUI: next_state = S_FETCH;
            default: next_state = S_FETCH;
        endcase
    end

    always_comb begin
        fetch_reg_we   = 1'b0;
        decode_reg_we  = 1'b0;
        execute_reg_we = 1'b0;
        mem_reg_we     = 1'b0;
        wb_result_we   = 1'b0;
        pc_reg_we      = 1'b0;
        reg_we         = 1'b0;
        alu_src1_sel   = `ALU_SRC1_RS1;
        alu_src2_sel   = 1'b0;
        alu_control    = `ADD;
        wb_src_sel     = `WB_SRC_ALU;
        data_funct3    = funct3;
        d_write        = 1'b0;
        d_valid        = 1'b0;
        i_valid        = 1'b0;
        branch_control = funct3;
        branch_valid   = 1'b0;
        pc_next_sel    = `PC_NEXT_PC4;

        case (state)
            S_FETCH: begin
                i_valid = 1'b1;
                if (i_ready)
                    fetch_reg_we = 1'b1;
            end

            S_DECODE: begin
                decode_reg_we = 1'b1;
                // LUI는 EX/MEM을 거치지 않고도 write-back 데이터가 확정된다.
                // 이 시점에 WB 결과 레지스터에 immediate를 저장해둔다.
                if (opcode == `LUI_TYPE) begin
                    wb_result_we = 1'b1;
                    wb_src_sel   = `WB_SRC_IMM;
                end
            end

            S_EX_ALU: begin
                execute_reg_we = 1'b1;
                wb_result_we   = 1'b1;
                // EX 단계는 DECODE에서 저장한 제어값만 사용한다.
                alu_src1_sel   = ex_alu_src1_sel_reg;
                alu_src2_sel   = ex_alu_src2_sel_reg;
                alu_control    = ex_alu_control_reg;
                wb_src_sel     = `WB_SRC_ALU;
            end

            S_EX_ADDR: begin
                execute_reg_we = 1'b1;
                alu_src1_sel   = ex_alu_src1_sel_reg;
                alu_src2_sel   = ex_alu_src2_sel_reg;
                alu_control    = ex_alu_control_reg;
            end

            S_EX_BRANCH: begin
                execute_reg_we = 1'b1;
                alu_src1_sel   = ex_alu_src1_sel_reg;
                alu_src2_sel   = ex_alu_src2_sel_reg;
                alu_control    = ex_alu_control_reg;
                branch_control = dec_funct3_reg;
                branch_valid   = 1'b1;
            end

            S_BRANCH_COMMIT: begin
                pc_reg_we      = 1'b1;
                branch_control = dec_funct3_reg;
                branch_valid   = 1'b1;
                pc_next_sel    = `PC_NEXT_BRANCH;
            end

            S_EX_JUMP: begin
                execute_reg_we = 1'b1;
                wb_result_we   = 1'b1;
                alu_src1_sel   = ex_alu_src1_sel_reg;
                alu_src2_sel   = ex_alu_src2_sel_reg;
                alu_control    = ex_alu_control_reg;
                wb_src_sel     = `WB_SRC_PC4;
            end

            S_MEM_READ: begin
                d_valid = 1'b1;
                wb_src_sel = `WB_SRC_MEM;
                if (d_ready) begin
                    mem_reg_we = 1'b1;
                    wb_result_we = 1'b1;
                end
            end

            S_MEM_WRITE: begin
                d_valid = 1'b1;
                d_write = 1'b1;
                if (d_ready) begin
                    pc_reg_we   = 1'b1;
                    pc_next_sel = `PC_NEXT_PC4;
                end
            end

            S_WB_ALU: begin
                reg_we      = 1'b1;
                wb_src_sel  = `WB_SRC_ALU;
                pc_reg_we   = 1'b1;
                pc_next_sel = `PC_NEXT_PC4;
            end

            S_WB_LOAD: begin
                reg_we      = 1'b1;
                wb_src_sel  = `WB_SRC_MEM;
                data_funct3 = dec_funct3_reg;
                pc_reg_we   = 1'b1;
                pc_next_sel = `PC_NEXT_PC4;
            end

            S_WB_JUMP: begin
                reg_we     = 1'b1;
                wb_src_sel = `WB_SRC_PC4;
                pc_reg_we  = 1'b1;
                if (dec_opcode_reg == `JALR_TYPE)
                    pc_next_sel = `PC_NEXT_RS1_IMM;
                else
                    pc_next_sel = `PC_NEXT_JUMP;
            end

            S_WB_LUI: begin
                reg_we      = 1'b1;
                wb_src_sel  = `WB_SRC_IMM;
                pc_reg_we   = 1'b1;
                pc_next_sel = `PC_NEXT_PC4;
            end

            default: begin
            end
        endcase
    end
endmodule
