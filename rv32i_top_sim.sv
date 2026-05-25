`timescale 1ns / 1ps

module rv32i_top_sim;
    logic clk;
    logic rst;
    logic [15:0] led;

    rv32i_top dut (
        .clk(clk),
        .rst(rst),
        .led(led)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst = 1'b0;
        repeat (20) @(posedge clk);
        $finish;
    end

    always @(posedge clk) begin
        $display(
            "t=%0t pc=%h instr=%h d_valid=%b d_write=%b d_addr=%h d_wdata=%h PSEL=%b PADDR=%h PWDATA=%h slv1_data0=%h led=%h",
            $time,
            dut.i_addr,
            dut.i_rdata,
            dut.d_valid,
            dut.d_write,
            dut.d_addr,
            dut.d_wdata,
            dut.PSEL,
            dut.PADDR,
            dut.PWDATA,
            dut.slv1_data0,
            led
        );
    end
endmodule
