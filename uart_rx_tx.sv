`timescale 1ns / 1ps

module uart_rx_tx #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer OVERSAMPLE  = 16
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] baud_divisor,
    input  logic        rx,
    output logic        tx,
 
    input  logic        tx_start,
    input  logic [ 7:0] tx_data_in,
    output logic        tx_busy,
    output logic        tx_done,
 
    output logic [ 7:0] rx_data_out,
    output logic        rx_valid
);

    logic baud_tick;

    baudrate_tick_gen #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .OVERSAMPLE (OVERSAMPLE)
    ) U_BAUDRATE_TICK_GEN (
        .clk         (clk),
        .rst         (rst),
        .baud_divisor(baud_divisor),
        .baud_tick   (baud_tick)
    );

    uart_tx #(
        .OVERSAMPLE(OVERSAMPLE)
    ) U_UART_TX (
        .clk      (clk),
        .rst      (rst),
        .baud_tick(baud_tick),
        .tx_start (tx_start),
        .tx_data  (tx_data_in),
        .tx       (tx),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    uart_rx #(
        .OVERSAMPLE(OVERSAMPLE)
    ) U_UART_RX (
        .clk      (clk),
        .rst      (rst),
        .baud_tick(baud_tick),
        .rx       (rx),
        .rx_data  (rx_data_out),
        .rx_valid (rx_valid)
    );

endmodule


module baudrate_tick_gen #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer OVERSAMPLE  = 16
) (
    input  logic [31:0] baud_divisor,
    input  logic        clk,
    input  logic        rst,
    output logic        baud_tick
);

    logic [31:0] tick_count;
    logic [31:0] divisor_safe;

    always_comb begin
        if (baud_divisor == 0) begin
            divisor_safe = 32'd1;
        end else begin
            divisor_safe = baud_divisor;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_count <= 32'd0;
            baud_tick  <= 1'b0;
        end else if (tick_count >= (divisor_safe - 1'b1)) begin
            tick_count <= 32'd0;
            baud_tick  <= 1'b1;
        end else begin
            tick_count <= tick_count + 1;
            baud_tick  <= 1'b0;
        end
    end

endmodule


module uart_tx #(
    parameter integer OVERSAMPLE = 16
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       baud_tick,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx,
    output logic       tx_busy,
    output logic       tx_done
);

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } tx_state_t;

    tx_state_t state;
    logic [7:0] tx_shift_reg;
    logic [3:0] sample_count;
    logic [2:0] bit_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= TX_IDLE;
            tx_shift_reg <= 8'h00;
            sample_count <= 4'd0;
            bit_count    <= 3'd0;
            tx           <= 1'b1;
            tx_busy      <= 1'b0;
            tx_done      <= 1'b0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                TX_IDLE: begin
                    tx           <= 1'b1;
                    tx_busy      <= 1'b0;
                    sample_count <= 4'd0;
                    bit_count    <= 3'd0;

                    if (tx_start) begin
                        tx_shift_reg <= tx_data;
                        tx_busy      <= 1'b1;
                        state        <= TX_START;
                    end
                end

                TX_START: begin
                    tx <= 1'b0;
                    if (baud_tick) begin
                        if (sample_count == OVERSAMPLE - 1) begin
                            sample_count <= 4'd0;
                            state        <= TX_DATA;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                TX_DATA: begin
                    tx <= tx_shift_reg[0];
                    if (baud_tick) begin
                        if (sample_count == OVERSAMPLE - 1) begin
                            sample_count <= 4'd0;
                            tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};

                            if (bit_count == 3'd7) begin
                                bit_count <= 3'd0;
                                state     <= TX_STOP;
                            end else begin
                                bit_count <= bit_count + 1'b1;
                            end
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1;
                    if (baud_tick) begin
                        if (sample_count == OVERSAMPLE - 1) begin
                            sample_count <= 4'd0;
                            tx_busy      <= 1'b0;
                            tx_done      <= 1'b1;
                            state        <= TX_IDLE;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= TX_IDLE;
                end
            endcase
        end
    end

endmodule


module uart_rx #(
    parameter integer OVERSAMPLE = 16
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       baud_tick,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_valid
);

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    rx_state_t state;
    logic [7:0] rx_shift_reg;
    logic [3:0] sample_count;
    logic [2:0] bit_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= RX_IDLE;
            rx_shift_reg <= 8'h00;
            sample_count <= 4'd0;
            bit_count    <= 3'd0;
            rx_data      <= 8'h00;
            rx_valid     <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                RX_IDLE: begin
                    sample_count <= 4'd0;
                    bit_count    <= 3'd0;

                    if (!rx) begin
                        state <= RX_START;
                    end
                end

                RX_START: begin
                    if (baud_tick) begin
                        if (sample_count == (OVERSAMPLE/2) - 1) begin
                            sample_count <= 4'd0;
                            if (!rx) begin
                                state <= RX_DATA;
                            end else begin
                                state <= RX_IDLE;
                            end
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                RX_DATA: begin
                    if (baud_tick) begin
                        if (sample_count == OVERSAMPLE - 1) begin
                            sample_count <= 4'd0;
                            rx_shift_reg <= {rx, rx_shift_reg[7:1]};

                            if (bit_count == 3'd7) begin
                                bit_count <= 3'd0;
                                state     <= RX_STOP;
                            end else begin
                                bit_count <= bit_count + 1'b1;
                            end
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                RX_STOP: begin
                    if (baud_tick) begin
                        if (sample_count == OVERSAMPLE - 1) begin
                            sample_count <= 4'd0;
                            if (rx) begin
                                rx_data  <= rx_shift_reg;
                                rx_valid <= 1'b1;
                            end
                            state <= RX_IDLE;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule


module uart_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 16
) (
    input                        clk,
    input                        rst,
    input                        wr_en,
    input                        rd_en,
    input      [DATA_WIDTH-1:0]  wdata,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                 full,
    output logic                 empty,
    output logic [4:0]           level
);

    localparam integer ADDR_W = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_W-1:0] wr_ptr;
    logic [ADDR_W-1:0] rd_ptr;
    logic [ADDR_W:0]   count;

    assign rdata = mem[rd_ptr];
    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign level = count[4:0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    mem[wr_ptr] <= wdata;
                    wr_ptr      <= wr_ptr + 1'b1;
                    count       <= count + 1'b1;
                end
                2'b01: begin
                    rd_ptr <= rd_ptr + 1'b1;
                    count  <= count - 1'b1;
                end
                2'b11: begin
                    mem[wr_ptr] <= wdata;
                    wr_ptr      <= wr_ptr + 1'b1;
                    rd_ptr      <= rd_ptr + 1'b1;
                end
                default: begin
                end
            endcase
        end
    end

endmodule
