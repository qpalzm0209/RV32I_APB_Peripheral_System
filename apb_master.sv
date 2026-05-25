`timescale 1ns / 1ps

module apb_master_example #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter SLAVE_NUM  = 4
) (
    input                       PCLK,
    input                       PRESETn,

    // CPU-side request
    input                       read_req,
    input                       write_req,
    input      [ADDR_WIDTH-1:0] addr,
    input      [2:0]            size,
    input      [DATA_WIDTH-1:0] wdata,
    output logic                ready,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                slverr,

    // APB master outputs
    output logic [ADDR_WIDTH-1:0] PADDR,
    output logic [SLAVE_NUM-1:0]  PSEL,
    output logic                  PENABLE,
    output logic                  PWRITE,
    output logic [2:0]            PSIZE,
    output logic [DATA_WIDTH-1:0] PWDATA,

    // APB slave responses
    input                         PSLVERR_0,
    input      [DATA_WIDTH-1:0]   PRDATA_0,
    input                         PREADY_0,
    input                         PSLVERR_1,
    input      [DATA_WIDTH-1:0]   PRDATA_1,
    input                         PREADY_1
    ,
    input                         PSLVERR_2,
    input      [DATA_WIDTH-1:0]   PRDATA_2,
    input                         PREADY_2,
    input                         PSLVERR_3,
    input      [DATA_WIDTH-1:0]   PRDATA_3,
    input                         PREADY_3
);

    typedef enum logic [1:0] {
        ST_IDLE   = 2'b00,
        ST_SETUP  = 2'b01,
        ST_ACCESS = 2'b10
    } state_t;

    state_t state, next_state;

    logic [ADDR_WIDTH-1:0] addr_reg;
    logic [DATA_WIDTH-1:0] wdata_reg;
    logic                  write_reg;
    logic [2:0]            size_reg;
    logic [2:0]            sel_idx;

    logic                  apb_pready;
    logic [DATA_WIDTH-1:0] apb_prdata;
    logic                  apb_pslverr;

    // 4KB window per slave:
    // 0x0000_0000 ~ 0x0000_0FFF -> slave 0 (dmem)
    // 0x0000_1000 ~ 0x0000_1FFF -> slave 1 (gpio)
    // 0x0000_2000 ~ 0x0000_2FFF -> slave 2 (fnd)
    // 0x0000_3000 ~ 0x0000_3FFF -> slave 3 (uart)
    always_comb begin
        unique case (addr_reg[15:12])
            4'h0: sel_idx = 3'd0;
            4'h1: sel_idx = 3'd1;
            4'h2: sel_idx = 3'd2;
            default: sel_idx = 3'd3;
        endcase
    end

    // Select one slave response and return a single response to the CPU side.
    always_comb begin
        apb_pready  = 1'b0;
        apb_prdata  = '0;
        apb_pslverr = 1'b0;

        unique case (sel_idx)
            3'd0: begin
                apb_pready  = PREADY_0;
                apb_prdata  = PRDATA_0;
                apb_pslverr = PSLVERR_0;
            end
            3'd1: begin
                apb_pready  = PREADY_1;
                apb_prdata  = PRDATA_1;
                apb_pslverr = PSLVERR_1;
            end
            3'd2: begin
                apb_pready  = PREADY_2;
                apb_prdata  = PRDATA_2;
                apb_pslverr = PSLVERR_2;
            end
            3'd3: begin
                apb_pready  = PREADY_3;
                apb_prdata  = PRDATA_3;
                apb_pslverr = PSLVERR_3;
            end
            default: begin
                apb_pready  = PREADY_3;
                apb_prdata  = PRDATA_3;
                apb_pslverr = PSLVERR_3;
            end
        endcase
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            state     <= ST_IDLE;
            addr_reg  <= '0;
            wdata_reg <= '0;
            write_reg <= 1'b0;
            size_reg  <= '0;
        end else begin
            state <= next_state;

            if (state == ST_IDLE && (read_req || write_req)) begin
                // CPU-side request fields are latched here before being renamed
                // onto the APB bus as PADDR / PSIZE / PWDATA.
                addr_reg  <= addr;
                wdata_reg <= wdata;
                write_reg <= write_req;
                size_reg  <= size;
            end
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (read_req || write_req) begin
                    next_state = ST_SETUP;
                end
            end
            ST_SETUP: begin
                next_state = ST_ACCESS;
            end
            ST_ACCESS: begin
                if (apb_pready) begin
                    next_state = ST_IDLE;
                end
            end
            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // APB output generation
    always_comb begin
        // Latched CPU-side request translated into APB naming.
        PADDR   = addr_reg;
        PWDATA  = wdata_reg;
        PWRITE  = write_reg;
        PSIZE   = size_reg;
        PENABLE = 1'b0;
        PSEL    = '0;

        case (state)
            ST_IDLE: begin
            end
            ST_SETUP: begin
                // Setup phase: drive address/control and select the target slave.
                PSEL[sel_idx] = 1'b1;
            end
            ST_ACCESS: begin
                // Access phase: keep address/control stable and assert PENABLE.
                PSEL[sel_idx] = 1'b1;
                PENABLE       = 1'b1;
            end
        endcase
    end

    // CPU-side response
    always_comb begin
        ready  = 1'b0;
        rdata  = '0;
        slverr = 1'b0;

        if (state == ST_ACCESS && apb_pready) begin
            ready  = 1'b1;
            rdata  = apb_prdata;
            slverr = apb_pslverr;
        end
    end

endmodule
