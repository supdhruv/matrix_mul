`timescale 1ns/1ps
module mac_tb;
    reg         clk, rst, en;
    reg  [17:0] a, b;
    wire [35:0] accum;

    mac #(.WIDTH(18)) uut(.clk(clk),.rst(rst),.en(en),.a(a),.b(b),.accum(accum));

    // 10ns clock
    always #5 clk = ~clk;

    initial begin
    $dumpfile("mac_tb.vcd");
    $dumpvars(0, mac_tb);
    clk = 0; rst = 1; en = 0;
    a = 0; b = 0;

    // Hold reset for 3 full clock cycles — not just 1
    repeat(3) @(posedge clk);
    #1; rst = 0;

    // Wait one more idle cycle before enabling
    @(posedge clk); #1;

    // Test 1: 3×4 + 2×5 + 1×6 = 28
    en = 1;
    a = 18'd3; b = 18'd4; @(posedge clk); #1;
    a = 18'd2; b = 18'd5; @(posedge clk); #1;
    a = 18'd1; b = 18'd6; @(posedge clk); #1;
    en = 0;
    @(posedge clk); #1;
    $display("Result: %0d (expect 28)", accum);

    // Test 2: mid-reset
    rst = 1; repeat(2) @(posedge clk); #1;
    rst = 0; @(posedge clk); #1;
    $display("After mid-reset: %0d (expect 0)", accum);

    // Test 3: large values
    en = 1;
    a = 18'd131071; b = 18'd131071; @(posedge clk); #1;
    a = 18'd131071; b = 18'd131071; @(posedge clk); #1;
    en = 0; @(posedge clk); #1;
    $display("Large value result: %0d", accum);

    $finish;
end
endmodule