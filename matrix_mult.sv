`timescale 1ns / 1ps
module matrix_mult #(
    parameter N     = 4,
    parameter WIDTH = 18
)(
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      start,
    input  wire [N*N*WIDTH-1:0]      m1_flat,
    input  wire [N*N*WIDTH-1:0]      m2_flat,
    output reg  [N*N*2*WIDTH-1:0]    res_flat,
    output reg                       done
);

    // ── unpack inputs ─────────────────────────────────────────
    wire [WIDTH-1:0] m1 [0:N-1][0:N-1];
    wire [WIDTH-1:0] m2 [0:N-1][0:N-1];

    generate
        genvar gi, gj;                          // ← moved INSIDE generate
        for (gi = 0; gi < N; gi++) begin : unpack_rows
            for (gj = 0; gj < N; gj++) begin : unpack_cols
                assign m1[gi][gj] = m1_flat[(gi*N+gj)*WIDTH +: WIDTH];
                assign m2[gi][gj] = m2_flat[(gi*N+gj)*WIDTH +: WIDTH];
            end
        end
    endgenerate

    // ── counter k ─────────────────────────────────────────────
    // ── FSM ───────────────────────────────────────────────────
reg [$clog2(N+1)-1:0] k;   // one extra bit for safety
reg running;

initial begin
    done    = 0;
    running = 0;
    k       = 0;
end

always @(posedge clk) begin
    if (rst) begin
        k       <= 0;
        running <= 0;
        done    <= 0;
    end else if (start) begin
        k       <= 0;
        running <= 1;
        done    <= 0;
    end else if (running) begin
        if (k == N-1) begin
            running <= 0;
            done    <= 1;    // stays high until next start/rst
            k       <= 0;
        end else begin
            k    <= k + 1;
            done <= 0;
        end
    end
    // removed the else done<=0 - let done stay high
end

// ── MAC array ─────────────────────────────────────────────
generate
    genvar i, j;
    for (i = 0; i < N; i++) begin : row
        for (j = 0; j < N; j++) begin : col

            reg [2*WIDTH-1:0] acc;

            // Accumulate
            always @(posedge clk) begin
                if (rst || start)
                    acc <= 0;
                else if (running)
                    acc <= acc + m1[i][k] * m2[k][j];
            end

            // Latch into res_flat one cycle after done
            always @(posedge clk) begin
                if (rst || start)
                    res_flat[(i*N+j)*2*WIDTH +: 2*WIDTH] <= 0;
                // CORRECT — latch at the exact moment running ends
else if (running && k == N-1)
    res_flat[(i*N+j)*2*WIDTH +: 2*WIDTH] <= acc + m1[i][k] * m2[k][j];
            end

        end
    end
endgenerate
endmodule