# Course decryption baseline

This separate testbench checks notebook case 4: all 882 ciphertext blocks from
`crypto/rsa/inp_messages/ct4_in.txt`, with the notebook's exact 256-bit modulus
and private exponent. It leaves the hardware and existing testbenches unchanged.

Run from the repository root:

```sh
sh Exponentiation/testbench/run_course_baseline.sh
```

Quick one-block check:

```sh
sh Exponentiation/testbench/run_course_baseline.sh -gMAX_BLOCKS=1
```

The runner builds in a temporary directory and cleans it up afterwards. GHDL
must be installed. The full run simulates tens of millions of clock edges and
can take an hour or more of real time on this machine. Use the one-block
check for quick iteration and reserve the full run for final verification.
Any mismatch or handshake timeout fails the run. Only the full run prints `FULL COURSE CASE 4: ALL 882 BLOCKS PASSED`.

## Vectors

The checked-in hex files contain one 256-bit integer per line. Each original
32-byte file block is interpreted little endian, matching the notebook's word
conversion and the RTL interface. Hex text prints the most significant digit
first, as expected by VHDL `hread`.

Expected values were calculated using Python `pow(ciphertext, d, n)` and checked
against every byte of the archive's `otp_sw_messages/pt4_out.txt`. The archive's
hardware outputs are not used as references. Regenerate with:

```sh
python3 Exponentiation/testbench/generate_course_vectors.py /path/to/files_for_the_pynq_sd_card.zip
```

## Interpreting results

The test reports latency from each accepted input to its accepted result, plus
batch time including input handshakes. Reset is excluded. The clock period is
10 ns (100 MHz), so divide batch cycles by 100,000 for milliseconds. This is an
assumed FPGA clock, not a measured maximum frequency.

This exercises the exponentiation unit with output ready continuously asserted.
It does not model DMA, AXI serializers, Python overhead, packet boundaries,
output stalls, or a multicore dispatcher. The measured notebook time was about
890 ms for this file; use the simulation to explain the arithmetic portion,
not to claim a complete board-runtime prediction.

The existing RTL may emit a `numeric_std` metavalue warning at time zero before
its internal operands initialize. The runner keeps warnings visible.

## Recorded baseline (2026-11-10)

Hardware commit: `5ba7ba3`, branch `simulation/course-baseline`.

- All six original `exponentiation_tb` tests passed unchanged.
- The first two consecutive course case-4 blocks passed: **100,868 latency cycles each**.
- Including its input handshake: **100,869 batch cycles** per block.
- Projected 882-block batch: **88,966,458 cycles = 889.66458 ms at 100 MHz**.
- Notebook board measurement supplied by the user: **889.99081 ms**.

The 882 input/expected pairs were all verified in Python against the supplied
software reference. The full 882-block RTL simulation was started, then stopped
because of its runtime; it has **not** been claimed as passing. The total above
is a projection from the measured per-block latency. The current controller's cycle
count depends on the fixed exponent, not the message value.

The board comparison assumes the tested bitstream uses this RTL at 100 MHz;
that clock and bitstream provenance have not been independently verified here.
