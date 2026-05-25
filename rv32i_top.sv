`timescale 1ns / 1ps

module rv32i_top (
    input        clk,
    input        rst,
    input  [15:0] sw,
    input        uart_rx,
    output       uart_tx,
    output [15:0] led,
    output [6:0] seg,
    output       dp,
    output [3:0] an
);
    logic        i_valid, i_ready;
    logic [31:0] i_addr, i_rdata;

    logic        d_valid, d_write, d_ready;
    logic [2:0]  d_funct3;
    logic [31:0] d_addr, d_wdata, d_rdata;
    logic [2:0]  d_size;

    logic [31:0] PADDR, PWDATA;
    logic [3:0]  PSEL;
    logic        PENABLE, PWRITE;
    logic [2:0]  PSIZE;

    logic        dmem_pslverr, dmem_pready;
    logic [31:0] dmem_prdata;

    logic        gpio_pslverr, gpio_pready;
    logic [31:0] gpio_prdata;

    logic        fnd_pslverr, fnd_pready;
    logic [31:0] fnd_prdata;
    logic [15:0] fnd_value;

    logic        uart_pslverr, uart_pready;
    logic [31:0] uart_prdata;

    tri   [31:0] GPIO;

    instruction_mem U_INSTRUCTION_MEM (
        .instr_addr(i_addr),
        .instr_data(i_rdata)
    );

    rv32i_cpu U_RV32I_CPU (
        .clk     (clk),
        .rst     (rst),
        .i_valid (i_valid),
        .i_addr  (i_addr),
        .i_rdata (i_rdata),
        .i_ready (i_ready),
        .d_valid (d_valid),
        .d_write (d_write),
        .d_addr  (d_addr),
        .d_funct3(d_funct3),
        .d_wdata (d_wdata),
        .d_rdata (d_rdata),
        .d_ready (d_ready)
    );

    assign d_size = d_funct3;

    apb_master_example U_APB_MASTER (
        .PCLK     (clk),
        .PRESETn  (~rst),
        .read_req (d_valid && !d_write),
        .write_req(d_valid && d_write),
        .addr     (d_addr),
        .size     (d_size),
        .wdata    (d_wdata),
        .ready    (d_ready),
        .rdata    (d_rdata),
        .slverr   (),
        .PADDR    (PADDR),
        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PSIZE    (PSIZE),
        .PWDATA   (PWDATA),
        .PSLVERR_0(dmem_pslverr),
        .PRDATA_0 (dmem_prdata),
        .PREADY_0 (dmem_pready),
        .PSLVERR_1(gpio_pslverr),
        .PRDATA_1 (gpio_prdata),
        .PREADY_1 (gpio_pready),
        .PSLVERR_2(fnd_pslverr),
        .PRDATA_2 (fnd_prdata),
        .PREADY_2 (fnd_pready),
        .PSLVERR_3(uart_pslverr),
        .PRDATA_3 (uart_prdata),
        .PREADY_3 (uart_pready)
    );

    apb_dmem_slave U_APB_DMEM_SLAVE (
        .PCLK   (clk),
        .PRESETn(~rst),
        .PSEL   (PSEL[0]),
        .PADDR  (PADDR),
        .PENABLE(PENABLE),
        .PWRITE (PWRITE),
        .PSIZE  (PSIZE),
        .PWDATA (PWDATA),
        .PRDATA (dmem_prdata),
        .PREADY (dmem_pready),
        .PSLVERR(dmem_pslverr)
    );

    // GPIO[15:0]  : LED output
    // GPIO[31:16] : switch input
    assign GPIO[31:16] = sw;
    assign led         = GPIO[15:0];

    apb_gpio_slave U_APB_GPIO_SLAVE (
        .PCLK     (clk),
        .PRESETn  (~rst),
        .PADDR    (PADDR),
        .PWDATA   (PWDATA),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PSEL     (PSEL[1]),
        .PRDATA   (gpio_prdata),
        .PREADY   (gpio_pready),
        .PSLVERR  (gpio_pslverr),
        .GPIO_CTRL(32'h0000_FFFF),
        .GPIO     (GPIO)
    );

    apb_fnd_slave U_APB_FND_SLAVE (
        .PCLK   (clk),
        .PRESETn(~rst),
        .PSEL   (PSEL[2]),
        .PADDR  (PADDR),
        .PENABLE(PENABLE),
        .PWRITE (PWRITE),
        .PWDATA (PWDATA),
        .PRDATA (fnd_prdata),
        .PREADY (fnd_pready),
        .PSLVERR(fnd_pslverr),
        .fnd_value(fnd_value)
    );

    apb_uart_slave U_APB_UART_SLAVE (
        .PCLK   (clk),
        .PRESETn(~rst),
        .PSEL   (PSEL[3]),
        .PADDR  (PADDR),
        .PENABLE(PENABLE),
        .PWRITE (PWRITE),
        .PWDATA (PWDATA),
        .PRDATA (uart_prdata),
        .PREADY (uart_pready),
        .PSLVERR(uart_pslverr),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    fnd_hex4_driver U_FND_HEX4_DRIVER (
        .clk  (clk),
        .rst  (rst),
        .value(fnd_value),
        .seg  (seg),
        .dp   (dp),
        .an   (an)
    );

    assign i_ready = 1'b1;

endmodule


module fnd_hex4_driver (
    input        clk,
    input        rst,
    input  [15:0] value,
    output logic [6:0] seg,
    output logic       dp,
    output logic [3:0] an
);
    logic [1:0] scan_sel;
    logic [15:0] scan_div;
    logic [3:0] hex_digit;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scan_div <= 16'd0;
        end else begin
            scan_div <= scan_div + 1'b1;
        end
    end

    assign scan_sel = scan_div[15:14];
    assign dp       = 1'b1;

    always_comb begin
        an       = 4'b1111;
        hex_digit = 4'h0;

        unique case (scan_sel)
            2'd0: begin
                an       = 4'b1110;
                hex_digit = value[3:0];
            end
            2'd1: begin
                an       = 4'b1101;
                hex_digit = value[7:4];
            end
            2'd2: begin
                an       = 4'b1011;
                hex_digit = value[11:8];
            end
            default: begin
                an       = 4'b0111;
                hex_digit = value[15:12];
            end
        endcase
    end

    always_comb begin
        unique case (hex_digit)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            default: seg = 7'b0001110;
        endcase
    end

endmodule
