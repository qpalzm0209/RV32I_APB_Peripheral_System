`timescale 1ns / 1ps

module tb_multicycle_timing;
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
        .clk(clk),
        .rst(rst),
        .instr_addr(instr_addr),
        .data_rdata(data_rdata),
        .instr_data(instr_data),
        .data_we(data_we),
        .data_addr(data_addr),
        .data_funct3(data_funct3),
        .data_wdata(data_wdata)
    );

    data_mem dut_mem (
        .clk(clk),
        .rst(rst),
        .data_we(data_we),
        .i_funct3(data_funct3),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_rdata(data_rdata)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        for (int idx = 0; idx < 32; idx++) imem[idx] = 32'h00000013;
        imem[0] = 32'h00500093; // addi x1, x0, 5
        imem[1] = 32'h00308113; // addi x2, x1, 3
        imem[2] = 32'h0000006f; // jal  x0, 0

        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // FETCH captures instruction 0 and advances PC to 4.
        @(posedge clk); #1;
        if (instr_addr !== 32'd4)
            $fatal(1, "FETCH must advance PC to 4, got %0d", instr_addr);

        // ADDI must then spend DECODE, EXECUTE and WRITEBACK with PC held.
        repeat (3) begin
            @(posedge clk); #1;
            if (instr_addr !== 32'd4)
                $fatal(1, "PC changed before ADDI completed; got %0d", instr_addr);
        end

        // Only the next FETCH may advance to instruction 2.
        @(posedge clk); #1;
        if (instr_addr !== 32'd8)
            $fatal(1, "next FETCH must advance PC to 8, got %0d", instr_addr);

        repeat (4) @(posedge clk);
        #1;
        if (dut.U_DATAPATH.U_REG_FILE.reg_file[1] !== 32'd5)
            $fatal(1, "x1 writeback mismatch");

        $display("PASS: tb_multicycle_timing multi-cycle state timing");
        $finish;
    end
endmodule
