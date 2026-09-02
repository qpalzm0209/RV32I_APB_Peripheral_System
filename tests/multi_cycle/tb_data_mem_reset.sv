`timescale 1ns / 1ps

module tb_data_mem_reset;
    logic        clk;
    logic        rst;
    logic        data_we;
    logic [2:0]  i_funct3;
    logic [31:0] data_addr;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;

    data_mem dut (
        .clk(clk),
        .rst(rst),
        .data_we(data_we),
        .i_funct3(i_funct3),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_rdata(data_rdata)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst        = 1'b1;
        data_we    = 1'b0;
        i_funct3   = 3'b010;
        data_addr  = 32'd20;
        data_wdata = 32'hA1B2_C3D4;

        #1;
        if (data_rdata !== 32'd0)
            $fatal(1, "configuration-time data memory initialization failed");

        @(negedge clk);
        rst     = 1'b0;
        data_we = 1'b1;
        @(posedge clk);
        #1;
        data_we = 1'b0;

        if (data_rdata !== 32'hA1B2_C3D4)
            $fatal(1, "data memory write failed");

        // Runtime reset intentionally leaves data memory contents unchanged.
        rst = 1'b1;
        #1;
        rst = 1'b0;

        if (data_rdata !== 32'hA1B2_C3D4)
            $fatal(1, "runtime reset unexpectedly cleared data memory");

        $display("PASS: tb_data_mem_reset data memory persists across reset");
        $finish;
    end
endmodule
