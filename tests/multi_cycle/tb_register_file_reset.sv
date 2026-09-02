`timescale 1ns / 1ps

module tb_register_file_reset;
    logic        clk;
    logic        rst;
    logic [4:0]  read_addr1;
    logic [4:0]  read_addr2;
    logic [4:0]  write_addr;
    logic        reg_we;
    logic [31:0] write_data;
    logic [31:0] read_data1;
    logic [31:0] read_data2;

    register_file dut (
        .clk(clk),
        .rst(rst),
        .read_addr1(read_addr1),
        .read_addr2(read_addr2),
        .write_addr(write_addr),
        .reg_we(reg_we),
        .write_data(write_data),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst        = 1'b1;
        read_addr1 = 5'd5;
        read_addr2 = 5'd0;
        write_addr = 5'd0;
        reg_we     = 1'b0;
        write_data = 32'd0;

        #1;
        if ((read_data1 !== 32'd0) || (read_data2 !== 32'd0))
            $fatal(1, "reset register reads must return zero");

        @(negedge clk);
        rst        = 1'b0;
        write_addr = 5'd5;
        write_data = 32'hdeadbeef;
        reg_we     = 1'b1;
        @(posedge clk);
        #1;
        reg_we = 1'b0;

        if (read_data1 !== 32'hdeadbeef)
            $fatal(1, "register write/read mismatch");

        rst = 1'b1;
        #1;
        if (read_data1 !== 32'd0)
            $fatal(1, "runtime reset exposed stale RAM data");

        rst = 1'b0;
        #1;
        if (read_data1 !== 32'd0)
            $fatal(1, "invalid register must remain zero after reset release");

        write_addr = 5'd0;
        write_data = 32'hffffffff;
        reg_we     = 1'b1;
        @(posedge clk);
        #1;
        if (read_data2 !== 32'd0)
            $fatal(1, "x0 must remain hardwired to zero");

        $display("PASS: tb_register_file_reset LUTRAM reset semantics");
        $finish;
    end
endmodule
