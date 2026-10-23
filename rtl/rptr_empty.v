// rptr_empty.v - read pointer and empty flag (read clock domain)
//
// Empty when the next read pointer equals the synchronized write pointer.

module rptr_empty #(
    parameter ADDR_WIDTH = 4
) (
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    input  wire [ADDR_WIDTH:0]   rq2_wptr,   // write pointer, synchronized, Gray
    output reg                   rempty,
    output wire [ADDR_WIDTH-1:0] raddr,
    output reg  [ADDR_WIDTH:0]   rptr        // read pointer, Gray
);
    reg  [ADDR_WIDTH:0] rbin;
    wire [ADDR_WIDTH:0] rbin_next  = rbin + {{ADDR_WIDTH{1'b0}}, rinc & ~rempty};
    wire [ADDR_WIDTH:0] rgray_next = (rbin_next >> 1) ^ rbin_next;
    wire rempty_next = (rgray_next == rq2_wptr);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= {(ADDR_WIDTH + 1){1'b0}};
            rptr   <= {(ADDR_WIDTH + 1){1'b0}};
            rempty <= 1'b1;
        end else begin
            rbin   <= rbin_next;
            rptr   <= rgray_next;
            rempty <= rempty_next;
        end
    end

    assign raddr = rbin[ADDR_WIDTH-1:0];
endmodule
