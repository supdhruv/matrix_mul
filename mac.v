`timescale 1ns / 1ps
module mac #(
    parameter WIDTH = 18
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  en,
    input  wire  [WIDTH-1:0]     a,
    input  wire  [WIDTH-1:0]     b,
    output reg   [2*WIDTH-1:0]   accum
);
    always @(posedge clk) begin
        if (rst)
            accum <= 0;
        else if (en)
            accum <= accum + (a * b);
    end
endmodule