`timescale 1ns / 1ps

module apb_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input                         PCLK,
    input                         PRESETn,
    input                         PSEL,
    input        [ADDR_WIDTH-1:0] PADDR,
    input                         PENABLE,
    input                         PWRITE,
    input        [DATA_WIDTH-1:0] PWDATA,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PREADY,
    output logic                  PSLVERR,
    input        [DATA_WIDTH-1:0] ext_status,
    output logic [DATA_WIDTH-1:0] reg_ctrl,
    output logic [DATA_WIDTH-1:0] reg_data0,
    output logic [DATA_WIDTH-1:0] reg_data1
);

    logic [3:0] addr_word;
    logic       apb_write;
    logic       apb_read;
    logic       addr_valid;

    localparam REG_CTRL_ADDR   = 4'h0;
    localparam REG_DATA0_ADDR  = 4'h1;
    localparam REG_DATA1_ADDR  = 4'h2;
    localparam REG_STATUS_ADDR = 4'h3;

    assign addr_word = PADDR[5:2];
    assign apb_write = PSEL && PENABLE && PWRITE && addr_valid;
    assign apb_read  = PSEL && PENABLE && !PWRITE && addr_valid;

    always_comb begin
        addr_valid = 1'b0;
        unique case (addr_word)
            REG_CTRL_ADDR,
            REG_DATA0_ADDR,
            REG_DATA1_ADDR,
            REG_STATUS_ADDR: addr_valid = 1'b1;
            default:         addr_valid = 1'b0;
        endcase
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_ctrl  <= '0;
            reg_data0 <= '0;
            reg_data1 <= '0;
        end else if (apb_write) begin
            unique case (addr_word)
                REG_CTRL_ADDR : reg_ctrl  <= PWDATA;
                REG_DATA0_ADDR: reg_data0 <= PWDATA;
                REG_DATA1_ADDR: reg_data1 <= PWDATA;
                default: begin
                end
            endcase
        end
    end

    always_comb begin
        PRDATA = '0;
        if (apb_read) begin
            unique case (addr_word)
                REG_CTRL_ADDR  : PRDATA = reg_ctrl;
                REG_DATA0_ADDR : PRDATA = reg_data0;
                REG_DATA1_ADDR : PRDATA = reg_data1;
                REG_STATUS_ADDR: PRDATA = ext_status;
                default        : PRDATA = '0;
            endcase
        end
    end

    assign PREADY  = 1'b1;
    assign PSLVERR = (PSEL && PENABLE) && !addr_valid;

endmodule


module apb_dmem_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input                         PCLK,
    input                         PRESETn,
    input                         PSEL,
    input        [ADDR_WIDTH-1:0] PADDR,
    input                         PENABLE,
    input                         PWRITE,
    input        [2:0]            PSIZE,
    input        [DATA_WIDTH-1:0] PWDATA,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PREADY,
    output logic                  PSLVERR
);

    logic        data_we;
    logic [31:0] data_addr;
    logic [31:0] data_rdata;

    assign data_we   = PSEL && PENABLE && PWRITE;
    assign data_addr = {20'd0, PADDR[11:0]};
    assign PRDATA    = data_rdata;
    assign PREADY    = 1'b1;
    assign PSLVERR   = 1'b0;

    data_mem U_DATA_MEM (
        .clk       (PCLK),
        .rst       (~PRESETn),
        .data_we   (data_we),
        .i_funct3  (PSIZE),
        .data_addr (data_addr),
        .data_wdata(PWDATA),
        .data_rdata(data_rdata)
    );

endmodule


module apb_gpio_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input                         PCLK,
    input                         PRESETn,
    input        [ADDR_WIDTH-1:0] PADDR,
    input        [DATA_WIDTH-1:0] PWDATA,
    input                         PENABLE,
    input                         PWRITE,
    input                         PSEL,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PREADY,
    output logic                  PSLVERR,
    input        [DATA_WIDTH-1:0] GPIO_CTRL,
    inout        [DATA_WIDTH-1:0] GPIO
);

    logic [3:0]            addr_word;
    logic                  apb_write;
    logic                  apb_read;
    logic                  addr_valid;
    logic [DATA_WIDTH-1:0] reg_odata;
    logic [DATA_WIDTH-1:0] gpio_idata;

    localparam GPIO_CTRL_ADDR  = 4'h0;
    localparam GPIO_ODATA_ADDR = 4'h1;
    localparam GPIO_IDATA_ADDR = 4'h2;

    assign addr_word = PADDR[5:2];
    assign apb_write = PSEL && PENABLE && PWRITE;
    assign apb_read  = PSEL && PENABLE && !PWRITE;

    always_comb begin
        addr_valid = 1'b0;
        unique case (addr_word)
            GPIO_CTRL_ADDR,
            GPIO_ODATA_ADDR,
            GPIO_IDATA_ADDR: addr_valid = 1'b1;
            default:         addr_valid = 1'b0;
        endcase
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_odata <= '0;
        end else if (apb_write && addr_valid) begin
            unique case (addr_word)
                GPIO_ODATA_ADDR: reg_odata <= PWDATA;
                default: begin
                end
            endcase
        end
    end

    always_comb begin
        PRDATA = '0;
        if (apb_read) begin
            unique case (addr_word)
                GPIO_CTRL_ADDR : PRDATA = GPIO_CTRL;
                GPIO_ODATA_ADDR: PRDATA = reg_odata;
                GPIO_IDATA_ADDR: PRDATA = gpio_idata;
                default        : PRDATA = '0;
            endcase
        end
    end

    genvar gpio_idx;
    generate
        for (gpio_idx = 0; gpio_idx < DATA_WIDTH; gpio_idx = gpio_idx + 1) begin : GEN_GPIO_BUF
            gpio_triode U_GPIO_TRIODE (
                .ctrl  (GPIO_CTRL[gpio_idx]),
                .o_data(reg_odata[gpio_idx]),
                .gpio  (GPIO[gpio_idx]),
                .i_data(gpio_idata[gpio_idx])
            );
        end
    endgenerate

    assign PREADY  = 1'b1;
    assign PSLVERR = (PSEL && PENABLE) && !addr_valid;

endmodule


module gpio_triode (
    input  ctrl,
    input  o_data,
    inout  gpio,
    output i_data
);

    assign gpio   = ctrl ? o_data : 1'bz;
    assign i_data = gpio;

endmodule


module apb_fnd_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input                         PCLK,
    input                         PRESETn,
    input                         PSEL,
    input        [ADDR_WIDTH-1:0] PADDR,
    input                         PENABLE,
    input                         PWRITE,
    input        [DATA_WIDTH-1:0] PWDATA,
    output logic [DATA_WIDTH-1:0] PRDATA,
    output logic                  PREADY,
    output logic                  PSLVERR,
    output logic [15:0]           fnd_value
);

    logic [3:0] addr_word;
    logic       apb_write;
    logic       apb_read;
    logic       addr_valid;

    localparam REG_FNDDATA_ADDR = 4'h0;

    assign addr_word = PADDR[5:2];
    assign apb_write = PSEL && PENABLE && PWRITE;
    assign apb_read  = PSEL && PENABLE && !PWRITE;
    assign addr_valid = (addr_word == REG_FNDDATA_ADDR);

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            fnd_value <= 16'h0000;
        end else if (apb_write && addr_valid) begin
            fnd_value <= PWDATA[15:0];
        end
    end

    always_comb begin
        PRDATA = '0;
        if (apb_read && addr_valid) begin
            PRDATA = {16'h0000, fnd_value};
        end
    end

    assign PREADY  = 1'b1;
    assign PSLVERR = (PSEL && PENABLE) && !addr_valid;

endmodule


module apb_uart_slave(
    input               PCLK,
    input               PRESETn,
    input               PSEL,
    input        [31:0] PADDR,
    input               PENABLE,
    input               PWRITE,
    input        [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,
    input               uart_rx,
    output logic        uart_tx
);
    logic [3:0]  addr_word;
    logic        apb_write;
    logic        apb_read;
    logic        addr_valid;

    logic [31:0] reg_baudrate;
    logic [31:0] reg_baud_divisor;
    logic [31:0] state;
    logic [31:0] reg_rx_data;
    logic [31:0] tx_fifo_wdata;
    logic [7:0]  tx_fifo_rdata;
    logic [7:0]  rx_fifo_rdata;
    logic [7:0]  uart_rx_data;

    logic tx_fifo_wr_en;
    logic tx_fifo_rd_en;
    logic tx_fifo_full;
    logic tx_fifo_empty;
    logic [4:0] tx_fifo_level;

    logic rx_fifo_wr_en;
    logic rx_fifo_rd_en;
    logic rx_fifo_full;
    logic rx_fifo_empty;
    logic [4:0] rx_fifo_level;

    logic uart_tx_start;
    logic uart_tx_busy;
    logic uart_tx_done;
    logic uart_rx_valid;
    logic rx_overrun;

    localparam REG_BAUDRATE_ADDR = 4'h0;
    localparam REG_STATE_ADDR    = 4'h1;
    localparam REG_RXDATA_ADDR   = 4'h2;
    localparam REG_TXDATA_ADDR   = 4'h3;

    function automatic [31:0] baud_to_divisor(input [31:0] baud_rate_value);
        begin
            unique case (baud_rate_value)
                32'd4_800  : baud_to_divisor = 32'd1302;
                32'd9_600  : baud_to_divisor = 32'd651;
                32'd19_200 : baud_to_divisor = 32'd326;
                32'd38_400 : baud_to_divisor = 32'd163;
                32'd57_600 : baud_to_divisor = 32'd109;
                32'd115_200: baud_to_divisor = 32'd54;
                32'd230_400: baud_to_divisor = 32'd27;
                default    : baud_to_divisor = 32'd651;
            endcase
        end
    endfunction

    assign addr_word   = PADDR[5:2];
    assign apb_write   = PSEL && PENABLE && PWRITE;
    assign apb_read    = PSEL && PENABLE && !PWRITE;
    assign addr_valid  = (addr_word == REG_BAUDRATE_ADDR) ||
                         (addr_word == REG_STATE_ADDR)    ||
                         (addr_word == REG_RXDATA_ADDR)   ||
                         (addr_word == REG_TXDATA_ADDR);

    assign tx_fifo_wdata = PWDATA;
    assign tx_fifo_wr_en = apb_write && (addr_word == REG_TXDATA_ADDR) && !tx_fifo_full;
    assign rx_fifo_rd_en = apb_read  && (addr_word == REG_RXDATA_ADDR) && !rx_fifo_empty;
    assign tx_fifo_rd_en = !uart_tx_busy && !tx_fifo_empty;
    assign uart_tx_start = tx_fifo_rd_en;
    assign rx_fifo_wr_en = uart_rx_valid && !rx_fifo_full;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_baudrate <= 32'd9600;
            reg_baud_divisor <= 32'd651;
            reg_rx_data  <= '0;
            rx_overrun   <= 1'b0;
        end else begin
            if (apb_write && (addr_word == REG_BAUDRATE_ADDR)) begin
                reg_baudrate     <= PWDATA;
                reg_baud_divisor <= baud_to_divisor(PWDATA);
            end

            if (uart_rx_valid) begin
                if (!rx_fifo_full) begin
                    reg_rx_data <= {24'h0, uart_rx_data};
                end else begin
                    rx_overrun <= 1'b1;
                end
            end

            if (rx_fifo_rd_en) begin
                reg_rx_data <= {24'h0, rx_fifo_rdata};
            end
        end
    end

    always_comb begin
        state        = '0;
        state[0]     = tx_fifo_full;
        state[1]     = tx_fifo_empty;
        state[2]     = rx_fifo_full;
        state[3]     = rx_fifo_empty;
        state[4]     = uart_tx_busy;
        state[5]     = !rx_fifo_empty;
        state[6]     = rx_overrun;
        state[12:8]  = tx_fifo_level;
        state[20:16] = rx_fifo_level;
    end

    always_comb begin
        PRDATA = '0;
        if (apb_read && addr_valid) begin
            unique case (addr_word)
                REG_BAUDRATE_ADDR: PRDATA = reg_baudrate;
                REG_STATE_ADDR   : PRDATA = state;
                REG_RXDATA_ADDR  : PRDATA = reg_rx_data;
                REG_TXDATA_ADDR  : PRDATA = 32'h0000_0000;
                default          : PRDATA = '0;
            endcase
        end
    end

    assign PREADY  = 1'b1;
    assign PSLVERR = (PSEL && PENABLE) &&
                     (!addr_valid ||
                      ((addr_word == REG_TXDATA_ADDR) && PWRITE && tx_fifo_full));

    uart_fifo #(
        .DATA_WIDTH(8),
        .DEPTH     (16)
    ) U_TX_FIFO (
        .clk   (PCLK),
        .rst   (~PRESETn),
        .wr_en (tx_fifo_wr_en),
        .rd_en (tx_fifo_rd_en),
        .wdata (tx_fifo_wdata[7:0]),
        .rdata (tx_fifo_rdata),
        .full  (tx_fifo_full),
        .empty (tx_fifo_empty),
        .level (tx_fifo_level)
    );

    uart_fifo #(
        .DATA_WIDTH(8),
        .DEPTH     (16)
    ) U_RX_FIFO (
        .clk   (PCLK),
        .rst   (~PRESETn),
        .wr_en (rx_fifo_wr_en),
        .rd_en (rx_fifo_rd_en),
        .wdata (uart_rx_data),
        .rdata (rx_fifo_rdata),
        .full  (rx_fifo_full),
        .empty (rx_fifo_empty),
        .level (rx_fifo_level)
    );

    uart_rx_tx U_UART_RX_TX (
        .clk        (PCLK),
        .rst        (~PRESETn),
        .baud_divisor(reg_baud_divisor),
        .rx         (uart_rx),
        .tx         (uart_tx),
        .tx_start   (uart_tx_start),
        .tx_data_in (tx_fifo_rdata),
        .tx_busy    (uart_tx_busy),
        .tx_done    (uart_tx_done),
        .rx_data_out(uart_rx_data),
        .rx_valid   (uart_rx_valid)
    );

endmodule
