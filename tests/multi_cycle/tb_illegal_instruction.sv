`timescale 1ns / 1ps

module tb_illegal_instruction;
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
        imem[0] = 32'h03700093; // addi x1, x0, 55
        // Illegal R encoding: funct7=0100000 is not valid for SLL.
        imem[1] = 32'h400010b3;
        imem[2] = 32'h04d00113; // addi x2, x0, 77
        // Illegal load funct3=011 must not overwrite x2.
        imem[3] = 32'h00003103;
        imem[4] = 32'h02100193; // addi x3, x0, 33
        // Illegal JALR funct3=001 must neither write x3 nor jump to 28.
        imem[5] = 32'h01c011e7;
        imem[6] = 32'h02c00213; // addi x4, x0, 44 (must execute)
        imem[7] = 32'h0000006f; // jal x0, 0

        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        repeat (50) @(posedge clk);
        #1;

        if (dut.U_DATAPATH.U_REG_FILE.reg_file[1] !== 32'd55)
            $fatal(1, "illegal R encoding changed x1");
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[2] !== 32'd77)
            $fatal(1, "illegal load encoding changed x2");
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[3] !== 32'd33)
            $fatal(1, "illegal JALR encoding changed x3");
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[4] !== 32'd44)
            $fatal(1, "illegal JALR encoding changed control flow");

        $display("PASS: tb_illegal_instruction side effects suppressed");
        $finish;
    end
endmodule
