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
    logic [7:0]  dmem[0:127];
    logic [31:0] load_word;

    // Assemble a little-endian 32-bit word from byte-addressed memory.
    assign load_word = {
        dmem[data_addr+3],
        dmem[data_addr+2],
        dmem[data_addr+1],
        dmem[data_addr]
    };

    initial begin
        for (int idx = 0; idx < 128; idx = idx + 1) begin
            dmem[idx] = 8'd0;
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int idx = 0; idx < 128; idx = idx + 1) begin
                dmem[idx] <= 8'd0;
            end
        end else if (data_we) begin
            // Store width is selected by funct3.
            unique case (i_funct3)
                // SB
                3'b000: dmem[data_addr] <= data_wdata[7:0];
                // SH
                3'b001: begin
                    dmem[data_addr]   <= data_wdata[7:0];
                    dmem[data_addr+1] <= data_wdata[15:8];
                end
                // SW
                3'b010: begin
                    dmem[data_addr]   <= data_wdata[7:0];
                    dmem[data_addr+1] <= data_wdata[15:8];
                    dmem[data_addr+2] <= data_wdata[23:16];
                    dmem[data_addr+3] <= data_wdata[31:24];
                end
                default: begin
                end
            endcase
        end
    end

    always_comb begin
        // Load width and sign extension are also controlled by funct3.
        unique case (i_funct3)
            // LB
            3'b000: data_rdata = {{24{dmem[data_addr][7]}}, dmem[data_addr]};
            // LH
            3'b001: data_rdata = {{16{dmem[data_addr+1][7]}}, dmem[data_addr+1], dmem[data_addr]};
            // LW
            3'b010: data_rdata = load_word;
            // LBU
            3'b100: data_rdata = {24'd0, dmem[data_addr]};
            // LHU
            3'b101: data_rdata = {16'd0, dmem[data_addr+1], dmem[data_addr]};
            default: data_rdata = 32'd0;
        endcase
    end
endmodule
