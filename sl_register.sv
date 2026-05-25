`timescale 1ns / 1ps

module sl_register(
    input               clk,
    input               rst,
    input               we,
    input        [31:0] write_data,
    output logic [31:0] read_data
);
    logic [31:0] reg_file;

    always_ff@(posedge clk, posedge rst) begin
        if (rst) begin
            reg_file[31:0] <= 32'b0;
        end else if (we) begin
            reg_file[31:0] <= write_data[31:0];
        end
    end

    assign read_data[31:0]  = reg_file[31:0] ;
endmodule

