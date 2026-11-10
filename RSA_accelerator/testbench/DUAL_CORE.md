# Parallel RSA cores

`rsa_core` now instantiates eight exponentiation units by default. The
multicore testbench also defaults to eight; use `CORE_COUNT=1` or `2` for
comparisons. The fully verified historical baseline used two cores.
The added `C_CORE_COUNT` generic supports one core for comparison and larger
counts for experiments. The existing accelerator instantiation needs no port
changes, and its key registers, DMA interface, and status value are unchanged.

Inputs are assigned in round-robin order. Results retire in the same order.
Each exponentiation unit holds its completed result until its turn, including
under downstream stalls. A separate packet-end flag is captured per core.
The exponentiation units capture the message and keys at the input handshake.
Reset clears both scheduling pointers and discards outstanding operations.

This simple scheduling can wait for the next assigned core even when another
core is idle. With a fixed exponent, blocks have equal compute latency, making
this a reasonable first design. It prioritizes predictable ordering over a
more complex dispatcher and result reorder buffer.

## Quick checks

From the repository root:

```sh
sh RSA_accelerator/testbench/run_multicore.sh
sh RSA_accelerator/testbench/run_multicore.sh -gCORE_COUNT=1
```

These use short exponents but retain the real 256-bit arithmetic. They check
reset during work, different keys and moduli on consecutive blocks, a slow
operation followed by a fast one, ordered results, multiple packets, output
stalls, stable output during stalls, and non-multiple batch sizes. No build
outputs are written into the checkout. The final quick batch uses a fixed short
exponent to compare throughput at equal work per block; it is not a private-key
performance measurement.

## Course comparison (long runs)

These runs use all 882 course decryption blocks and compare every result and
packet flag. RTL simulation can take an hour or more; run these when convenient:

```sh
sh RSA_accelerator/testbench/run_multicore.sh -gCORE_COUNT=1 -gCOURSE_BLOCKS=882
sh RSA_accelerator/testbench/run_multicore.sh -gCORE_COUNT=2 -gCOURSE_BLOCKS=882
```

For a shorter course-key check, use `-gCOURSE_BLOCKS=4`. Read the final batch's
cycle count, not the earlier quick-test batches. Both comparisons use the same
wrapper and testbench, isolating core count. Convert cycles to milliseconds at
100 MHz by dividing by 100,000. Two cores ideally approach 445 ms for this file
at the same clock, versus the existing approximately 890 ms baseline. These
are cycle-based expectations, not measured FPGA improvements.

This test exercises the 256-bit message interface, not the AXI serializers or
DMA. It does not replace end-to-end hardware testing.

## FPGA validation

Regenerate the accelerator project/IP, rebuild the SoC, and export a fresh
matching `.bit`/`.hwh` pair using the project's normal Vivado flow. Inspect
post-route utilization and timing; maintaining 100 MHz is not guaranteed.
Run all six RSA notebook cases on the board and compare repeated timings.
No register-map or notebook changes are required just to select eight cores.

At verified baseline `90fbcdc`, the single-core arithmetic source files were
unchanged. Subsequent clock/datapath timing candidates are described in
`TIMING_CHANGES.md` and need their own full-course and routed verification.
The original exponentiation-only baseline still tests a single arithmetic unit.

## Initial verification

Quick integration checks passed for core counts 1, 2, and 3. The fixed-key
32-block benchmark passed with 1 and 2 cores:

| Cores | Batch cycles | Simulated time at 100 MHz |
| --- | ---: | ---: |
| 1 | 33,248 | 0.33248 ms |
| 2 | 16,625 | 0.16625 ms |

That is approximately 2x throughput on this short-exponent test. The mixed-key
functional batches deliberately have uneven operation times and are not the
performance benchmark. The full two-core course run passed, as recorded below.
Vivado implementation of this two-core design remains to be performed. No FPGA runtime or utilization improvement has yet been
measured. The pre-existing time-zero numeric_std warning remains visible.

## Full course verification supplied by the user

The full GHDL run with `CORE_COUNT=2` and `COURSE_BLOCKS=882` completed:

- `FULL COURSE CASE 4 PASSED`
- `MULTICORE INTEGRATION TESTS PASSED`
- Course batch: **44,483,230 cycles**, or **444.83230 ms** at the assumed 100 MHz.

All 882 results and packet flags matched. This is a message-interface RTL
simulation, not a routed timing result or an FPGA runtime measurement. The
supplied routed reports describe the older single-core design and show
**WNS -4.987 ns at 100 MHz**, plus primary-clock definition warnings. Address
those issues and obtain new routed reports before claiming reliable 100 MHz
operation of the parallel design.

## Eight-core experiment

The default core count is eight. No scheduling or arithmetic change accompanies
this count change. To run the eight-core full course test explicitly:

```sh
sh RSA_accelerator/testbench/run_multicore.sh -gCORE_COUNT=8 -gCOURSE_BLOCKS=882
```

882 blocks require 111 groups of up to eight. At the existing per-block latency,
the expected arithmetic time is roughly **112 ms at 100 MHz**, including the
partly filled final group. This is a simulation projection. The earlier 53%
LUT estimate was based on the old single-core arithmetic; the carry-save timing
candidate and scheduling can change that estimate. A new Vivado implementation
must confirm fit, clock constraints, and timing. The complete 882-block pass
recorded above belongs to the earlier two-core baseline, not this experiment.

Eight-core short integration checks passed, including stalls, reset, packet
flags, ordering, and filling all eight cores. The 32-block fixed-key batch
completed in **4,163 cycles**, versus 33,248 with one core (about 7.99x
throughput). GHDL synthesis also passed. The eight-core full course simulation
and Vivado routed verification have not been performed.
