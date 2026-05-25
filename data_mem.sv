`timescale 1ns / 1ps

module data_mem (
    input         clk,
    input         rst,
    input         data_we,
    input  [2:0]  i_funct3,
    input  [31:0] data_addr,
    input  [31:0] data_wdata,
    output logic [31:0] data_rdata
);
    localparam WORD_DEPTH = 1024;  // 4KB / 4B

    (* ram_style = "block" *) logic [31:0] dmem[0:WORD_DEPTH-1];

    logic [9:0]  word_addr;
    logic [31:0] word_rdata;

    assign word_addr  = data_addr[11:2];
    assign word_rdata = dmem[word_addr];

    initial begin
        for (int idx = 0; idx < WORD_DEPTH; idx = idx + 1) begin
            dmem[idx] = 32'd0;
        end
    end

    always_ff @(posedge clk) begin
        if (data_we) begin
            unique case (i_funct3)
                // SB
                3'b000: begin
                    unique case (data_addr[1:0])
                        2'b00: dmem[word_addr][7:0]   <= data_wdata[7:0];
                        2'b01: dmem[word_addr][15:8]  <= data_wdata[7:0];
                        2'b10: dmem[word_addr][23:16] <= data_wdata[7:0];
                        2'b11: dmem[word_addr][31:24] <= data_wdata[7:0];
                    endcase
                end
                // SH
                3'b001: begin
                    if (data_addr[1] == 1'b0)
                        dmem[word_addr][15:0]  <= data_wdata[15:0];
                    else
                        dmem[word_addr][31:16] <= data_wdata[15:0];
                end
                // SW
                3'b010: begin
                    dmem[word_addr] <= data_wdata;
                end
                default: begin
                end
            endcase
        end
    end

    always_comb begin
        unique case (i_funct3)
            // LB
            3'b000: begin
                unique case (data_addr[1:0])
                    2'b00: data_rdata = {{24{word_rdata[7]}}, word_rdata[7:0]};
                    2'b01: data_rdata = {{24{word_rdata[15]}}, word_rdata[15:8]};
                    2'b10: data_rdata = {{24{word_rdata[23]}}, word_rdata[23:16]};
                    default: data_rdata = {{24{word_rdata[31]}}, word_rdata[31:24]};
                endcase
            end
            // LH
            3'b001: begin
                if (data_addr[1] == 1'b0)
                    data_rdata = {{16{word_rdata[15]}}, word_rdata[15:0]};
                else
                    data_rdata = {{16{word_rdata[31]}}, word_rdata[31:16]};
            end
            // LW
            3'b010: data_rdata = word_rdata;
            // LBU
            3'b100: begin
                unique case (data_addr[1:0])
                    2'b00: data_rdata = {24'd0, word_rdata[7:0]};
                    2'b01: data_rdata = {24'd0, word_rdata[15:8]};
                    2'b10: data_rdata = {24'd0, word_rdata[23:16]};
                    default: data_rdata = {24'd0, word_rdata[31:24]};
                endcase
            end
            // LHU
            3'b101: begin
                if (data_addr[1] == 1'b0)
                    data_rdata = {16'd0, word_rdata[15:0]};
                else
                    data_rdata = {16'd0, word_rdata[31:16]};
            end
            default: data_rdata = 32'd0;
        endcase
    end
endmodule
