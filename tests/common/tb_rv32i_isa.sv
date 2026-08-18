`timescale 1ns / 1ps

module tb_rv32i_isa;
    localparam [6:0] OP_R     = 7'b0110011;
    localparam [6:0] OP_I     = 7'b0010011;
    localparam [6:0] OP_LOAD  = 7'b0000011;
    localparam [6:0] OP_STORE = 7'b0100011;
    localparam [6:0] OP_BRANCH= 7'b1100011;
    localparam [6:0] OP_LUI   = 7'b0110111;
    localparam [6:0] OP_AUIPC = 7'b0010111;
    localparam [6:0] OP_JAL   = 7'b1101111;
    localparam [6:0] OP_JALR  = 7'b1100111;

    logic        clk;
    logic        rst;
    logic [31:0] instr_addr;
    logic [31:0] instr_data;
    logic [31:0] data_rdata;
    logic        data_we;
    logic [31:0] data_addr;
    logic [2:0]  data_funct3;
    logic [31:0] data_wdata;
    logic [31:0] imem [0:127];

    function automatic [31:0] enc_r(
        input [6:0] funct7, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [4:0] rd, input [6:0] opcode
    );
        enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] enc_i(
        input [11:0] imm, input [4:0] rs1, input [2:0] funct3,
        input [4:0] rd, input [6:0] opcode
    );
        enc_i = {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] enc_s(
        input [11:0] imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [6:0] opcode
    );
        enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic [31:0] enc_b(
        input [12:0] imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [6:0] opcode
    );
        enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                 imm[4:1], imm[11], opcode};
    endfunction

    function automatic [31:0] enc_u(
        input [19:0] imm, input [4:0] rd, input [6:0] opcode
    );
        enc_u = {imm, rd, opcode};
    endfunction

    function automatic [31:0] enc_j(
        input [20:0] imm, input [4:0] rd, input [6:0] opcode
    );
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    task automatic check_reg(input int index, input [31:0] expected);
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[index] !== expected)
            $fatal(1, "x%0d expected %08h, got %08h", index, expected,
                   dut.U_DATAPATH.U_REG_FILE.reg_file[index]);
    endtask

    assign instr_data = imem[instr_addr[8:2]];

    rv32i_cpu dut (
        .clk(clk), .rst(rst), .instr_addr(instr_addr),
        .data_rdata(data_rdata), .instr_data(instr_data),
        .data_we(data_we), .data_addr(data_addr),
        .data_funct3(data_funct3), .data_wdata(data_wdata)
    );

    data_mem dut_mem (
        .clk(clk), .rst(rst), .data_we(data_we),
        .i_funct3(data_funct3), .data_addr(data_addr),
        .data_wdata(data_wdata), .data_rdata(data_rdata)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        for (int idx = 0; idx < 128; idx++) imem[idx] = 32'h00000013;

        imem[0]  = enc_i(12'd10, 5'd0, 3'b000, 5'd1, OP_I);       // addi
        imem[1]  = enc_i(12'd3,  5'd0, 3'b000, 5'd2, OP_I);
        imem[2]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OP_R); // add
        imem[3]  = enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd4, OP_R); // sub
        imem[4]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd5, OP_R); // sll
        imem[5]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b010, 5'd6, OP_R); // slt
        imem[6]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b011, 5'd7, OP_R); // sltu
        imem[7]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd8, OP_R); // xor
        imem[8]  = enc_r(7'b0000000, 5'd2, 5'd1, 3'b101, 5'd9, OP_R); // srl
        imem[9]  = enc_i(12'hff0, 5'd0, 3'b000, 5'd10, OP_I);     // -16
        imem[10] = enc_r(7'b0100000, 5'd2, 5'd10, 3'b101, 5'd11, OP_R); // sra
        imem[11] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd12, OP_R); // or
        imem[12] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd13, OP_R); // and
        imem[13] = enc_i(12'd0,  5'd10, 3'b010, 5'd14, OP_I);     // slti
        imem[14] = enc_i(12'd1,  5'd10, 3'b011, 5'd15, OP_I);     // sltiu
        imem[15] = enc_i(12'd15, 5'd1,  3'b100, 5'd16, OP_I);     // xori
        imem[16] = enc_i(12'd8,  5'd2,  3'b110, 5'd17, OP_I);     // ori
        imem[17] = enc_i(12'd6,  5'd1,  3'b111, 5'd18, OP_I);     // andi
        imem[18] = enc_i(12'd4,  5'd2,  3'b001, 5'd19, OP_I);     // slli
        imem[19] = enc_i(12'd1,  5'd1,  3'b101, 5'd20, OP_I);     // srli
        imem[20] = enc_i(12'h402,5'd10, 3'b101, 5'd21, OP_I);     // srai
        imem[21] = enc_u(20'h12345, 5'd22, OP_LUI);
        imem[22] = enc_u(20'h00001, 5'd23, OP_AUIPC);
        imem[23] = enc_i(12'd64, 5'd0, 3'b000, 5'd24, OP_I);
        imem[24] = enc_s(12'd0,  5'd10, 5'd24, 3'b000, OP_STORE); // sb
        imem[25] = enc_s(12'd2,  5'd1,  5'd24, 3'b001, OP_STORE); // sh
        imem[26] = enc_s(12'd4,  5'd3,  5'd24, 3'b010, OP_STORE); // sw
        imem[27] = enc_i(12'd0,  5'd24, 3'b000, 5'd25, OP_LOAD);  // lb
        imem[28] = enc_i(12'd0,  5'd24, 3'b100, 5'd26, OP_LOAD);  // lbu
        imem[29] = enc_i(12'd2,  5'd24, 3'b001, 5'd27, OP_LOAD);  // lh
        imem[30] = enc_i(12'd2,  5'd24, 3'b101, 5'd28, OP_LOAD);  // lhu
        imem[31] = enc_i(12'd4,  5'd24, 3'b010, 5'd29, OP_LOAD);  // lw
        imem[32] = enc_b(13'd8, 5'd3,  5'd29, 3'b000, OP_BRANCH); // beq
        imem[33] = enc_i(12'd1, 5'd0, 3'b000, 5'd24, OP_I);
        imem[34] = enc_b(13'd8, 5'd2,  5'd1,  3'b001, OP_BRANCH); // bne
        imem[35] = enc_i(12'd2, 5'd0, 3'b000, 5'd24, OP_I);
        imem[36] = enc_b(13'd8, 5'd0,  5'd10, 3'b100, OP_BRANCH); // blt
        imem[37] = enc_i(12'd3, 5'd0, 3'b000, 5'd24, OP_I);
        imem[38] = enc_b(13'd8, 5'd2,  5'd1,  3'b101, OP_BRANCH); // bge
        imem[39] = enc_i(12'd4, 5'd0, 3'b000, 5'd24, OP_I);
        imem[40] = enc_b(13'd8, 5'd1,  5'd2,  3'b110, OP_BRANCH); // bltu
        imem[41] = enc_i(12'd5, 5'd0, 3'b000, 5'd24, OP_I);
        imem[42] = enc_b(13'd8, 5'd2,  5'd1,  3'b111, OP_BRANCH); // bgeu
        imem[43] = enc_i(12'd6, 5'd0, 3'b000, 5'd24, OP_I);
        imem[44] = enc_s(12'd8, 5'd24, 5'd0, 3'b010, OP_STORE);  // branch signature
        imem[45] = enc_j(21'd8, 5'd31, OP_JAL);                  // link = 184
        imem[46] = enc_i(12'd7, 5'd0, 3'b000, 5'd24, OP_I);     // skipped
        imem[47] = enc_i(12'd208, 5'd0, 3'b000, 5'd24, OP_I);
        imem[48] = enc_i(12'd0, 5'd24, 3'b000, 5'd30, OP_JALR); // link = 196
        imem[49] = enc_i(12'd8, 5'd0, 3'b000, 5'd24, OP_I);     // skipped
        imem[52] = enc_i(12'd9, 5'd0, 3'b000, 5'd24, OP_I);
        imem[53] = enc_j(21'd0, 5'd0, OP_JAL);                   // halt loop

        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (320) @(posedge clk);
        #1;

        check_reg(0,  32'h00000000);
        check_reg(1,  32'h0000000a);
        check_reg(2,  32'h00000003);
        check_reg(3,  32'h0000000d);
        check_reg(4,  32'h00000007);
        check_reg(5,  32'h00000050);
        check_reg(6,  32'h00000000);
        check_reg(7,  32'h00000000);
        check_reg(8,  32'h00000009);
        check_reg(9,  32'h00000001);
        check_reg(10, 32'hfffffff0);
        check_reg(11, 32'hfffffffe);
        check_reg(12, 32'h0000000b);
        check_reg(13, 32'h00000002);
        check_reg(14, 32'h00000001);
        check_reg(15, 32'h00000000);
        check_reg(16, 32'h00000005);
        check_reg(17, 32'h0000000b);
        check_reg(18, 32'h00000002);
        check_reg(19, 32'h00000030);
        check_reg(20, 32'h00000005);
        check_reg(21, 32'hfffffffc);
        check_reg(22, 32'h12345000);
        check_reg(23, 32'h00001058);
        check_reg(24, 32'h00000009);
        check_reg(25, 32'hfffffff0);
        check_reg(26, 32'h000000f0);
        check_reg(27, 32'h0000000a);
        check_reg(28, 32'h0000000a);
        check_reg(29, 32'h0000000d);
        check_reg(30, 32'h000000c4);
        check_reg(31, 32'h000000b8);

        if ({dut_mem.dmem[11], dut_mem.dmem[10], dut_mem.dmem[9], dut_mem.dmem[8]}
            !== 32'h00000040)
            $fatal(1, "branch signature expected 64");

        $display("PASS: tb_rv32i_isa supported instruction regression");
        $finish;
    end
endmodule
