# Asynchronous FIFO for Clock-Domain Crossing

A parameterized dual-clock FIFO in Verilog, for passing data safely between two unrelated
clock domains, with a self-checking testbench.

## Architecture

```
            write clock domain                         read clock domain
  winc,wdata ──► wptr_full ──waddr──►  fifo_mem  ◄──raddr── rptr_empty ◄── rinc
                   │  ▲                 (dual-port)              │  ▲
              wptr │  │ wq2_rptr                 rdata ──►  rptr  │  │ rq2_wptr
              (Gray)  │                                   (Gray)  │  │
                   │  └────── sync_2ff ◄──────────────────────────┘  │
                   └────────────────────────────► sync_2ff ──────────┘
```

| Module | Role |
|---|---|
| `async_fifo` | top level |
| `fifo_mem` | 2^ADDR_WIDTH x DATA_WIDTH storage, written on `wclk`, read asynchronously (first-word fall-through) |
| `wptr_full` | binary + Gray write pointer, `wfull` flag |
| `rptr_empty` | binary + Gray read pointer, `rempty` flag |
| `sync_2ff` | 2-flop synchronizer (`ASYNC_REG`) carrying a Gray pointer into the other domain |

Parameters: `DATA_WIDTH` (default 8), `ADDR_WIDTH` (default 4, depth 16; must be >= 2).

## Design notes

- **Why Gray code.** A binary pointer can change several bits at once (0111 -> 1000). If the
  other clock samples it mid-transition, it can see any mix of old and new bits. A Gray
  pointer changes exactly one bit per increment, so a sample is always either the old or
  the new value.
- **Why two flops.** The first flop can go metastable when its input changes near the clock
  edge. The second flop gives it a full clock period to settle before anyone uses the value.
- **Why an extra pointer bit.** Pointers are ADDR_WIDTH+1 bits. Equal addresses mean either
  empty or full; the extra MSB (a "lap" bit) tells them apart.
- **Full condition.** The write side compares its next Gray pointer with the synchronized
  read pointer: full when the two MSBs differ and the remaining bits match. That is
  "write pointer is exactly one lap ahead" expressed in Gray code.
- **Empty condition.** The read side's next Gray pointer equals the synchronized write
  pointer.
- **Conservative flags.** The synchronized pointer is 2-3 cycles old. The write side
  therefore sees the FIFO as fuller than it is, and the read side sees it as emptier. Flags
  release late but never assert late, so overflow and underflow cannot happen.
- **Registered flags.** `wfull` / `rempty` are computed from the *next* pointer and
  registered, so they are glitch-free and valid in the same cycle as the pointer update.

## Testbench

`tb/tb_async_fifo.v` checks every word against a reference model and runs:

1. reset values (`rempty` = 1, `wfull` = 0)
2. fill to full, then hold `winc` high while full: the extra writes must be dropped
3. drain to empty, then hold `rinc` high while empty: the extra reads must be ignored
4. 15 000 words of random concurrent traffic at five clock/traffic combinations:
   fast writer / slow reader, the reverse, nearly equal clocks, writer bursts (sits at
   full), reader bursts (sits at empty)
5. asynchronous reset in the middle of traffic with data in flight, then 2 000 more words:
   no stale data may come out

Checked on every clock edge:

- read data matches the model, in order
- no write accepted when the FIFO already holds DEPTH words, no read from an empty FIFO
- `wfull` high whenever the FIFO holds DEPTH words, `rempty` high whenever it holds none
- Gray pointers change by at most one bit per clock

Ends with `PASS` or `FAIL: N errors`, plus a timeout guard against hangs.

## Running

Vivado simulator (Windows):

```bash
cd sim
run_xsim.bat
```

Icarus Verilog:

```bash
iverilog -g2005 -o fifo_tb rtl/*.v tb/tb_async_fifo.v
vvp fifo_tb
```

## Limitations

- Resets are asserted and released asynchronously. In silicon each domain should release
  its reset through its own reset synchronizer.
- No formal timing constraints are included. On an FPGA, the synchronizer inputs need
  `set_max_delay -datapath_only` (or `set_false_path`) constraints between the two clocks.
