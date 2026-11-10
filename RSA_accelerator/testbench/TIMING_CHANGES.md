# Timing changes following the verified dual-core baseline

The full course result at baseline commit `90fbcdc` was 44,483,230 cycles with
two cores (444.83230 ms at an assumed 100 MHz). The supplied routed reports were
for the older single-core design and failed setup timing: WNS -4.987 ns, with
the worst path inside the multiplier's accumulator feedback.

## Changes

1. Before packaging accelerator IP, `generate_IP.tcl` marks the standalone
   clock XDC as `USED_IN {synthesis implementation out_of_context}`. The IP's
   primary input clock definition must not override the processing-system
   clock inside the SoC. This follows AMD UG1118, Managing Out-of-Context
   Constraints:
   https://docs.amd.com/r/2023.1-English/ug1118-vivado-creating-packaging-custom-ip/Managing-Out-of-Context-Constraints

2. The multiplier computes its reduction candidates using carry-save
   compression. Previously a full-width addition fed full-width subtractors.
   Now each candidate compresses `2*S`, the selected `A`, and registered `-N`
   (or `-2*N`) with bit-local XOR/majority logic, followed by one carry-propagate
   addition. `-N` is calculated at input acceptance; `-2*N` is a shift of that
   register. The unreduced candidate remains a parallel ordinary addition.

For nonzero N and A < N, the invariant S < N gives T=2*S+b_i*A < 3*N. With k+2
bits, T-N and T-2*N have valid sign bits. The carry-save arithmetic is modulo
2^(k+2), preserving exactly the original reduction choices. B may use all k
bits. Zero modulus and A >= N remain outside the multiplier's supported input
contract. No pipeline stage or arithmetic algorithm change was introduced.

## Validation

Run the short suite from any directory:

```sh
python3 /path/to/project/Exponentiation/testbench/run_timing_checks.py
```

It generates deterministic edge/random vectors against Python `(a*b)%n`,
checks the 257-cycle multiplier latency, runs the original multiplier and
exponentiation tests, checks the one-/two-core wrapper, and runs GHDL synthesis.
All generated data/build files are temporary. Full course simulation is left
to the user via the existing multicore runner. Its cycle count should remain
unchanged; this experiment targets achievable frequency, not fewer cycles.

## Vivado handoff

Vivado is not installed on this Mac. These changes are candidates for timing
closure, not evidence that 100 MHz now passes. To evaluate them:

- Regenerate projects and repackage the accelerator IP using the updated
  scripts. Upgrade the SoC's IP and rebuild synthesis and implementation;
  stale packaged IP will retain the old arithmetic and/or clock constraints.
- Inspect the packaged constraint file properties to confirm the standalone
  clock is OOC-only. The integrated RSA clock should inherit `clk_fpga_0`.
- Refresh `report_methodology`, `report_clocks`, `report_timing_summary`, and
  hierarchical utilization after routing. Resolve any remaining clock
  redefinition warnings and require setup/hold timing to pass. The supplied
  report also had smaller violations outside the multiplier, which this
  arithmetic change does not directly address.
- Check the new critical path, frequency, and LUT cost. Vivado can reshape
  arithmetic during synthesis; a structural improvement in RTL does not
  guarantee a shorter routed path. Export a matching `.bit`/`.hwh` pair and run
  all notebook cases only after the implementation is validated.

The existing board constraints remain available for standalone project runs;
only their use when packaging the accelerator is changed. No false paths,
multicycle exceptions, or lower clock target were added to hide violations.

## Local check results

The short suite passed: 168 directed/random multiplier vectors, the original
8 multiplier and 6 exponentiation cases, one-/two-core integration tests, and
GHDL synthesis. The multiplier remains 257 cycles; the fixed-key 32-block
batches remain 33,248 cycles (one core) and 16,625 (two cores). A Tcl stub check
also exercised the new clock-file classification block; actual Vivado IP
packaging and routed timing remain unverified. The full 882-block pass belongs
to baseline `90fbcdc`; it has not been repeated after this arithmetic change.
