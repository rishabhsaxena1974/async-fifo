// async_fifo.v - dual-clock FIFO for clock-domain crossing
//
// Pointers are ADDR_WIDTH+1 bits: the extra MSB distinguishes "full" from "empty" when the
// addresses are equal. Each pointer is passed to the other domain in Gray code through a
// 2-flop synchronizer, so only one bit changes per increment and a sample taken mid-change
// is either the old or the new value, never a corrupt mix.
//
// Flags are conservative: the synchronized pointer lags by 2-3 cycles, so wfull may stay
// high (and rempty may stay high) a little longer than necessary, but never too short.
// That means no overflow and no underflow. Requires ADDR_WIDTH >= 2.

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4                  // depth = 2**ADDR_WIDTH
) (
    // write domain
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [DATA_WIDTH-1:0] wdata,
    output wire                  wfull,
    // read domain
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    output wire [DATA_WIDTH-1:0] rdata,
    output wire                  rempty
);
    wire [ADDR_WIDTH-1:0] waddr, raddr;
    wire [ADDR_WIDTH:0]   wptr, rptr;         // Gray-coded pointers
    wire [ADDR_WIDTH:0]   wq2_rptr, rq2_wptr; // after synchronization into the other domain

    sync_2ff #(.WIDTH(ADDR_WIDTH + 1)) u_sync_r2w (
        .clk(wclk), .rst_n(wrst_n), .d(rptr), .q(wq2_rptr));

    sync_2ff #(.WIDTH(ADDR_WIDTH + 1)) u_sync_w2r (
        .clk(rclk), .rst_n(rrst_n), .d(wptr), .q(rq2_wptr));

    fifo_mem #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_mem (
        .wclk(wclk), .wen(winc & ~wfull), .waddr(waddr), .wdata(wdata),
        .raddr(raddr), .rdata(rdata));

    wptr_full #(.ADDR_WIDTH(ADDR_WIDTH)) u_wptr_full (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wq2_rptr(wq2_rptr),
        .wfull(wfull), .waddr(waddr), .wptr(wptr));

    rptr_empty #(.ADDR_WIDTH(ADDR_WIDTH)) u_rptr_empty (
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rq2_wptr(rq2_wptr),
        .rempty(rempty), .raddr(raddr), .rptr(rptr));
endmodule
