`timescale 1ns / 1ps

module tb_control_flow_edges;
    localparam [6:0] OP_I      = 7'b0010011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;

    logic        clk;
    logic        rst;
    logic [31:0] instr_addr;
    logic [31:0] instr_data;
    logic [31:0] data_rdata;
    logic        data_we;
    logic [31:0] data_addr;
    logic [2:0]  data_funct3;
    logic [31:0] data_wdata;
    logic [31:0] imem [0:31];

    function automatic [31:0] enc_i(
        input [11:0] imm, input [4:0] rs1, input [2:0] funct3,
        input [4:0] rd, input [6:0] opcode
    );
        enc_i = {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic [31:0] enc_b(
        input [12:0] imm, input [4:0] rs2, input [4:0] rs1,
        input [2:0] funct3, input [6:0] opcode
    );
        enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                 imm[4:1], imm[11], opcode};
    endfunction

    function automatic [31:0] enc_j(
        input [20:0] imm, input [4:0] rd, input [6:0] opcode
    );
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    assign instr_data = imem[instr_addr[6:2]];

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
        for (int idx = 0; idx < 32; idx++) imem[idx] = 32'h00000013;
        imem[0]  = enc_i(12'd1, 5'd0, 3'b000, 5'd1, OP_I);
        imem[1]  = enc_i(12'd2, 5'd0, 3'b000, 5'd2, OP_I);
        imem[2]  = enc_b(13'd8, 5'd2, 5'd1, 3'b000, OP_BRANCH); // BEQ not taken
        imem[3]  = enc_i(12'd3, 5'd0, 3'b000, 5'd3, OP_I);
        imem[4]  = enc_b(13'd8, 5'd2, 5'd1, 3'b001, OP_BRANCH); // BNE taken
        imem[5]  = enc_i(12'd99, 5'd0, 3'b000, 5'd3, OP_I);    // skipped
        imem[6]  = enc_i(12'd3, 5'd0, 3'b000, 5'd4, OP_I);
        imem[7]  = enc_i(12'hfff, 5'd4, 3'b000, 5'd4, OP_I);   // decrement
        imem[8]  = enc_b(13'h1ffc, 5'd0, 5'd4, 3'b001, OP_BRANCH); // BNE -4
        imem[9]  = enc_j(21'd8, 5'd5, OP_JAL);                 // link = 40
        imem[10] = enc_i(12'd99, 5'd0, 3'b000, 5'd6, OP_I);   // skipped
        imem[11] = enc_i(12'd57, 5'd0, 3'b000, 5'd7, OP_I);   // odd target
        imem[12] = enc_i(12'd0, 5'd7, 3'b000, 5'd8, OP_JALR); // link = 52
        imem[13] = enc_i(12'd88, 5'd0, 3'b000, 5'd6, OP_I);   // skipped
        imem[14] = enc_i(12'd6, 5'd0, 3'b000, 5'd6, OP_I);
        imem[15] = enc_j(21'd0, 5'd0, OP_JAL);

        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (100) @(posedge clk);
        #1;

        if (dut.U_DATAPATH.U_REG_FILE.reg_file[3] !== 32'd3)
            $fatal(1, "not-taken/taken branch flow mismatch");
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[4] !== 32'd0)
            $fatal(1, "backward branch loop mismatch");
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[5] !== 32'd40)
            $fatal(1, "JAL link mismatch");
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[6] !== 32'd6)
            $fatal(1, "JAL/JALR target mismatch");
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[8] !== 32'd52)
            $fatal(1, "JALR link or bit-zero masking mismatch");

        $display("PASS: tb_control_flow_edges branch and jump edges");
        $finish;
    end
endmodule
