// tb_async_fifo.v - self-checking testbench for async_fifo
//
// A reference model (an array indexed by accepted-write / accepted-read counters) checks
// every word that comes out. Scenarios:
//   1. reset values
//   2. fill to full, write while full (must be ignored)
//   3. drain to empty, read while empty (must be ignored)
//   4. random concurrent traffic at several clock ratios, plus bursty full/empty stress
//   5. reset in the middle of traffic, then traffic again (no stale data may appear)
// Continuous checks: data order, no overflow/underflow, full asserted when occupancy hits
// DEPTH, empty asserted when occupancy is 0, Gray pointers change by at most one bit.

`timescale 1ns/1ps

module tb_async_fifo;
    localparam DW = 8;
    localparam AW = 4;
    localparam DEPTH = 1 << AW;

    reg           wclk = 0, rclk = 0;
    reg           wrst_n = 0, rrst_n = 0;
    reg           winc = 0, rinc = 0;
    reg  [DW-1:0] wdata = 0;
    wire [DW-1:0] rdata;
    wire          wfull, rempty;

    real wclk_half = 5.0;
    real rclk_half = 8.5;
    always #(wclk_half) wclk = ~wclk;
    always #(rclk_half) rclk = ~rclk;

    async_fifo #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW)) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty));

    // ------------------------------------------------------------ reference model + monitors
    reg [DW-1:0] model [0:1023];
    integer wr_count = 0, rd_count = 0, errors = 0;
    integer full_cycles = 0, empty_cycles = 0;
    reg [AW:0] prev_wptr = 0, prev_rptr = 0;

    function integer ones(input [AW:0] v);
        integer i;
        begin
            ones = 0;
            for (i = 0; i <= AW; i = i + 1)
                ones = ones + v[i];
        end
    endfunction

    always @(posedge wclk) if (wrst_n) begin
        if (wr_count - rd_count == DEPTH && !wfull) begin
            $display("%t ERROR: FIFO holds %0d words but wfull is low", $time, DEPTH);
            errors = errors + 1;
        end
        if (ones(dut.wptr ^ prev_wptr) > 1) begin
            $display("%t ERROR: Gray write pointer changed by more than one bit", $time);
            errors = errors + 1;
        end
        prev_wptr = dut.wptr;
        if (wfull) full_cycles = full_cycles + 1;
        if (winc && !wfull) begin
            if (wr_count - rd_count >= DEPTH) begin
                $display("%t ERROR: write accepted while FIFO already holds %0d words", $time, DEPTH);
                errors = errors + 1;
            end
            model[wr_count % 1024] = wdata;
            wr_count = wr_count + 1;
        end
    end

    always @(posedge rclk) if (rrst_n) begin
        if (wr_count == rd_count && !rempty) begin
            $display("%t ERROR: FIFO is empty but rempty is low", $time);
            errors = errors + 1;
        end
        if (ones(dut.rptr ^ prev_rptr) > 1) begin
            $display("%t ERROR: Gray read pointer changed by more than one bit", $time);
            errors = errors + 1;
        end
        prev_rptr = dut.rptr;
        if (rempty) empty_cycles = empty_cycles + 1;
        if (rinc && !rempty) begin
            if (rd_count >= wr_count) begin
                $display("%t ERROR: read accepted from an empty FIFO", $time);
                errors = errors + 1;
            end else if (rdata !== model[rd_count % 1024]) begin
                $display("%t ERROR: read #%0d got %h, expected %h",
                         $time, rd_count, rdata, model[rd_count % 1024]);
                errors = errors + 1;
            end
            rd_count = rd_count + 1;
        end
    end

    // ------------------------------------------------------------ stimulus helpers
    reg stop = 0;

    task check(input cond, input [8*64-1:0] msg);
        if (!cond) begin
            $display("%t ERROR: %0s", $time, msg);
            errors = errors + 1;
        end
    endtask

    task apply_reset;
        begin
            winc = 0;
            rinc = 0;
            #3.3;                                   // deliberately not aligned to either clock
            wrst_n = 0;
            rrst_n = 0;
            #1;
            check(rempty === 1'b1, "rempty not set by reset");
            check(wfull === 1'b0, "wfull not cleared by reset");
            repeat (3) @(posedge wclk);
            repeat (3) @(posedge rclk);
            wr_count = 0;
            rd_count = 0;
            prev_wptr = 0;
            prev_rptr = 0;
            wrst_n = 1;
            rrst_n = 1;
            repeat (3) @(posedge wclk);
        end
    endtask

    // write with probability wr_pct each wclk until `target` writes are accepted (or stop)
    task writer(input integer target, input integer wr_pct);
        begin
            while (!stop && wr_count < target) begin
                @(negedge wclk);
                winc  = ($unsigned($random) % 100) < wr_pct;
                wdata = $random;
            end
            @(negedge wclk) winc = 0;
        end
    endtask

    task reader(input integer target, input integer rd_pct);
        begin
            while (!stop && rd_count < target) begin
                @(negedge rclk);
                rinc = ($unsigned($random) % 100) < rd_pct;
            end
            @(negedge rclk) rinc = 0;
        end
    endtask

    task traffic(input integer n, input integer wr_pct, input integer rd_pct,
                 input real wh, input real rh);
        integer target;
        begin
            wclk_half = wh;
            rclk_half = rh;
            target = wr_count + n;
            fork
                writer(target, wr_pct);
                reader(target, rd_pct);
            join
            $display("  traffic wclk %0.1f ns / rclk %0.1f ns, w%0d%% r%0d%%: %0d words, errors so far %0d",
                     2 * wh, 2 * rh, wr_pct, rd_pct, n, errors);
        end
    endtask

    // ------------------------------------------------------------ test sequence
    integer i;

    initial begin
        $display("async_fifo testbench, DEPTH = %0d", DEPTH);
        apply_reset;

        // 2. fill to full, then try to overflow
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge wclk);
            winc  = 1;
            wdata = i * 7 + 3;
        end
        @(negedge wclk);
        check(wfull === 1'b1, "wfull not set after DEPTH writes");
        wdata = 8'hEE;                              // winc still high: these must be dropped
        repeat (4) @(negedge wclk);
        winc = 0;
        check(wr_count == DEPTH, "write accepted while full");
        $display("  fill to full: ok");

        // 3. drain to empty, then try to underflow
        @(negedge rclk);
        rinc = 1;
        wait (rd_count == DEPTH);
        repeat (4) @(negedge rclk);                 // rinc still high: reads while empty
        rinc = 0;
        check(rempty === 1'b1, "rempty not set after draining");
        check(rd_count == DEPTH, "read accepted while empty");
        $display("  drain to empty: ok");

        // 4. random concurrent traffic at several clock ratios
        traffic(3000, 60, 60, 5.0, 8.5);            // fast writer, slow reader
        traffic(3000, 60, 60, 8.5, 5.0);            // slow writer, fast reader
        traffic(3000, 70, 70, 5.0, 5.1);            // nearly equal clocks
        traffic(3000, 100, 25, 5.0, 6.3);           // writer bursts: lives near full
        traffic(3000, 25, 100, 6.3, 5.0);           // reader bursts: lives near empty

        // 5. reset in the middle of traffic
        wclk_half = 5.0;
        rclk_half = 7.3;
        fork
            writer(wr_count + 100000, 70);
            reader(wr_count + 100000, 50);
            begin #2345.6; stop = 1; end
        join
        stop = 0;
        $display("  reset with %0d words in flight", wr_count - rd_count);
        apply_reset;
        traffic(2000, 60, 60, 5.0, 7.3);

        $display("full seen for %0d wclk cycles, empty for %0d rclk cycles", full_cycles, empty_cycles);
        if (errors == 0)
            $display("PASS: all checks passed");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
