// wptr_full.v - write pointer and full flag (write clock domain)
//
// Full when the next write pointer has caught up with the read pointer one lap behind.
// In Gray code "one lap behind" means the two MSBs are inverted and the rest are equal.

module wptr_full #(
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [ADDR_WIDTH:0]   wq2_rptr,   // read pointer, synchronized, Gray
    output reg                   wfull,
    output wire [ADDR_WIDTH-1:0] waddr,
    output reg  [ADDR_WIDTH:0]   wptr        // write pointer, Gray
);
    reg  [ADDR_WIDTH:0] wbin;
    wire [ADDR_WIDTH:0] wbin_next  = wbin + {{ADDR_WIDTH{1'b0}}, winc & ~wfull};
    wire [ADDR_WIDTH:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire wfull_next = (wgray_next == {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1],
                                       wq2_rptr[ADDR_WIDTH-2:0]});

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= {(ADDR_WIDTH + 1){1'b0}};
            wptr  <= {(ADDR_WIDTH + 1){1'b0}};
            wfull <= 1'b0;
        end else begin
            wbin  <= wbin_next;
            wptr  <= wgray_next;
            wfull <= wfull_next;
        end
    end

    assign waddr = wbin[ADDR_WIDTH-1:0];
endmodule
