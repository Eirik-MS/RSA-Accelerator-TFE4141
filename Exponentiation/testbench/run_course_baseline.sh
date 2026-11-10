#!/bin/sh
# Build outside the checkout; remove generated files when the simulation ends.
set -eu
testbench_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
simulation_dir=$(mktemp -d)
trap 'rm -rf "$simulation_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$simulation_dir"
ghdl -a --std=08 \
  "$testbench_dir/../source/modular_multiplication.vhd" \
  "$testbench_dir/../source/exponentiation.vhd" \
  "$testbench_dir/course_baseline_tb.vhd"
ghdl -e --std=08 course_baseline_tb
ghdl -r --std=08 course_baseline_tb \
  "-gINPUT_FILE=$testbench_dir/course_vectors/ct4_in.hex" \
  "-gEXPECTED_FILE=$testbench_dir/course_vectors/pt4_expected.hex" \
  "$@" --assert-level=error --unbuffered
