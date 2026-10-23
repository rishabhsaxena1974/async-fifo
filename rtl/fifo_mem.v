// fifo_mem.v - dual-port storage: synchronous write on wclk, asynchronous read
//
// The asynchronous read makes the FIFO first-word-fall-through: rdata already shows the
// oldest word whenever rempty is low, and rinc pops it. Maps to distributed RAM on FPGAs.

module fifo_mem #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,
    input  wire                  wen,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output wire [DATA_WIDTH-1:0] rdata
);
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH) - 1];

    always @(posedge wclk)
        if (wen)
            mem[waddr] <= wdata;

    assign rdata = mem[raddr];
endmodule
