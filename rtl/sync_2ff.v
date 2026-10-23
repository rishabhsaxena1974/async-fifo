// sync_2ff.v - two-flop synchronizer for a multi-bit Gray-coded bus
//
// The first flop may go metastable when d changes near the clock edge; the second gives it
// a full clock period to resolve. Only safe for a bus because the source is Gray-coded
// (one bit changes at a time). ASYNC_REG keeps the two flops close together in the FPGA
// and tells the tools they form a synchronizer.

module sync_2ff #(
    parameter WIDTH = 1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] meta;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta <= {WIDTH{1'b0}};
            q    <= {WIDTH{1'b0}};
        end else begin
            meta <= d;
            q    <= meta;
        end
    end
endmodule
