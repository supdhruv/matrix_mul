`timescale 1ns / 1ps
// ─────────────────────────────────────────────────────────────
//  AXI-Lite wrapper for matrix_mult
//  Wraps the raw matrix_mult module so Python/PYNQ can talk to it
//
//  REGISTER MAP (word-aligned, 32-bit reads/writes):
//  Offset  Dir  Signal         Description
//  0x00    W    m1_element     value of one m1 element (18-bit)
//  0x04    W    m2_element     value of one m2 element (18-bit)
//  0x08    W    element_index  which element (0..N²-1)
//  0x0C    W    control        bit0=rst, bit1=start
//  0x10    R    done           1 when result is ready
//  0x14+   R    result[n]      res_flat element n (36-bit, read as 32-bit low word)
// ─────────────────────────────────────────────────────────────
module axi_wrapper #(
    parameter N                  = 4,
    parameter WIDTH              = 18,
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 8
)(
    // AXI-Lite slave interface (Vivado standard port names)
    input  wire                              S_AXI_ACLK,
    input  wire                              S_AXI_ARESETN,  // active LOW
    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    S_AXI_AWADDR,
    input  wire [2:0]                        S_AXI_AWPROT,
    input  wire                              S_AXI_AWVALID,
    output reg                               S_AXI_AWREADY,
    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]    S_AXI_WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]  S_AXI_WSTRB,
    input  wire                              S_AXI_WVALID,
    output reg                               S_AXI_WREADY,
    // Write response channel
    output reg  [1:0]                        S_AXI_BRESP,
    output reg                               S_AXI_BVALID,
    input  wire                              S_AXI_BREADY,
    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    S_AXI_ARADDR,
    input  wire [2:0]                        S_AXI_ARPROT,
    input  wire                              S_AXI_ARVALID,
    output reg                               S_AXI_ARREADY,
    // Read data channel
    output reg  [C_S_AXI_DATA_WIDTH-1:0]    S_AXI_RDATA,
    output reg  [1:0]                        S_AXI_RRESP,
    output reg                               S_AXI_RVALID,
    input  wire                              S_AXI_RREADY
);

    // ── internal signals ──────────────────────────────────────
    reg  [N*N*WIDTH-1:0]    m1_flat;
    reg  [N*N*WIDTH-1:0]    m2_flat;
    wire [N*N*2*WIDTH-1:0]  res_flat;
    reg                     core_rst;
    reg                     core_start;
    wire                    core_done;

    // staging registers for AXI write
    reg [17:0]              reg_m1_element;
    reg [17:0]              reg_m2_element;
    reg [7:0]               reg_index;
    reg [1:0]               reg_control;

    // ── instantiate your matrix multiplier ───────────────────
    matrix_mult #(.N(N), .WIDTH(WIDTH)) core (
        .clk      (S_AXI_ACLK),
        .rst      (core_rst),
        .start    (core_start),
        .m1_flat  (m1_flat),
        .m2_flat  (m2_flat),
        .res_flat (res_flat),
        .done     (core_done)
    );

    // ── AXI write logic ───────────────────────────────────────
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY <= 0;
            S_AXI_WREADY  <= 0;
            S_AXI_BVALID  <= 0;
            S_AXI_BRESP   <= 2'b00;
            m1_flat       <= 0;
            m2_flat       <= 0;
            core_rst      <= 1;   // hold reset on power-up
            core_start    <= 0;
            reg_index     <= 0;
        end else begin

            // auto-clear one-cycle pulses
            core_start <= 0;
            core_rst   <= 0;

            // accept write when both address and data are valid
            if (S_AXI_AWVALID && S_AXI_WVALID
                    && !S_AXI_AWREADY && !S_AXI_WREADY) begin

                S_AXI_AWREADY <= 1;
                S_AXI_WREADY  <= 1;

                // decode address (word-aligned: bits [7:2])
                case (S_AXI_AWADDR[7:2])

                    6'h00: begin  // 0x00 — m1 element value
                        // load into the slot pointed to by reg_index
                        m1_flat[reg_index * WIDTH +: WIDTH]
                            <= S_AXI_WDATA[WIDTH-1:0];
                    end

                    6'h01: begin  // 0x04 — m2 element value
                        m2_flat[reg_index * WIDTH +: WIDTH]
                            <= S_AXI_WDATA[WIDTH-1:0];
                    end

                    6'h02: begin  // 0x08 — element index
                        reg_index <= S_AXI_WDATA[7:0];
                    end

                    6'h03: begin  // 0x0C — control
                        // bit0 = rst, bit1 = start
                        core_rst   <= S_AXI_WDATA[0];
                        core_start <= S_AXI_WDATA[1];
                    end

                    default: ;   // ignore unknown addresses

                endcase

                // send write response
                S_AXI_BRESP  <= 2'b00;   // OKAY
                S_AXI_BVALID <= 1;

            end else begin
                S_AXI_AWREADY <= 0;
                S_AXI_WREADY  <= 0;
            end

            // clear BVALID once master accepts response
            if (S_AXI_BVALID && S_AXI_BREADY)
                S_AXI_BVALID <= 0;
        end
    end

    // ── AXI read logic ────────────────────────────────────────
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY <= 0;
            S_AXI_RVALID  <= 0;
            S_AXI_RDATA   <= 0;
            S_AXI_RRESP   <= 2'b00;
        end else begin

            if (S_AXI_ARVALID && !S_AXI_ARREADY) begin
                S_AXI_ARREADY <= 1;
                S_AXI_RVALID  <= 1;
                S_AXI_RRESP   <= 2'b00;   // OKAY

                case (S_AXI_ARADDR[7:2])

                    6'h04: begin  // 0x10 — done flag
                        S_AXI_RDATA <= {31'b0, core_done};
                    end

                    default: begin
                        // 0x14 and above — result elements
                        // address 0x14 = index 0, 0x18 = index 1 ...
                        if (S_AXI_ARADDR >= 8'h14) begin
                            automatic integer idx;
                            idx = (S_AXI_ARADDR - 8'h14) >> 2;
                            if (idx < N*N)
                                // return lower 32 bits of 36-bit result
                                S_AXI_RDATA <= res_flat[idx*2*WIDTH +: 32];
                            else
                                S_AXI_RDATA <= 32'hDEADBEEF; // invalid
                        end else
                            S_AXI_RDATA <= 32'h0;
                    end

                endcase

            end else begin
                S_AXI_ARREADY <= 0;
            end

            // clear RVALID once master accepts data
            if (S_AXI_RVALID && S_AXI_RREADY)
                S_AXI_RVALID <= 0;

        end
    end

endmodule
