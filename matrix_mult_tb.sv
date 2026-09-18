`timescale 1ns/1ps
module matrix_mult_tb;
    parameter N = 2, WIDTH = 18;

    reg  clk, rst, start;
    reg  [N*N*WIDTH-1:0]     m1_flat, m2_flat;
    wire [N*N*2*WIDTH-1:0]   res_flat;
    wire done;

    matrix_mult #(.N(N),.WIDTH(WIDTH)) uut(
        .clk(clk),.rst(rst),.start(start),
        .m1_flat(m1_flat),.m2_flat(m2_flat),
        .res_flat(res_flat),.done(done)
    );

    always #5 clk = ~clk;

    // Helper task to pack a value into flat bus
    // m1 = [[1,2],[3,4]]  m2 = [[5,6],[7,8]]
    // Expected: C[0][0]=1*5+2*7=19  C[0][1]=1*6+2*8=22
    //           C[1][0]=3*5+4*7=43  C[1][1]=3*6+4*8=50

    initial begin
        $dumpfile("matrix_mult_tb.vcd");
        $dumpvars(0, matrix_mult_tb);
        clk = 0; rst = 1; start = 0;

        // Pack m1 = [[1,2],[3,4]]
        m1_flat = 0;
       // NEW — explicit row*N+col indexing
m1_flat[(0*N+0)*WIDTH +: WIDTH] = 18'd1;  // m1[0][0]
m1_flat[(0*N+1)*WIDTH +: WIDTH] = 18'd2;  // m1[0][1]
m1_flat[(1*N+0)*WIDTH +: WIDTH] = 18'd3;  // m1[1][0]
m1_flat[(1*N+1)*WIDTH +: WIDTH] = 18'd4;  // m1[1][1]

m2_flat[(0*N+0)*WIDTH +: WIDTH] = 18'd5;  // m2[0][0]
m2_flat[(0*N+1)*WIDTH +: WIDTH] = 18'd6;  // m2[0][1]
m2_flat[(1*N+0)*WIDTH +: WIDTH] = 18'd7;  // m2[1][0]
m2_flat[(1*N+1)*WIDTH +: WIDTH] = 18'd8;  // m2[1][1]

       // NEW — hold reset 3 cycles
repeat(3) @(posedge clk); #1;
rst = 0;
repeat(2) @(posedge clk); #1;
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;

        // Wait for done
        // Wait for done
@(posedge done);
@(posedge clk); #1;   // ← add this — let res_flat latch
@(posedge clk); #1;   // ← and this

$display("C[0][0] = %0d (expect 19)", res_flat[0*2*WIDTH +: 2*WIDTH]);
$display("C[0][1] = %0d (expect 22)", res_flat[1*2*WIDTH +: 2*WIDTH]);
$display("C[1][0] = %0d (expect 43)", res_flat[2*2*WIDTH +: 2*WIDTH]);
$display("C[1][1] = %0d (expect 50)", res_flat[3*2*WIDTH +: 2*WIDTH]);

        $finish;
    end
endmodule