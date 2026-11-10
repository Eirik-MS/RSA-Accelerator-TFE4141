#!/bin/sh
set -eu
testbench_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$testbench_dir/../.." && pwd)
simulation_dir=$(mktemp -d)
trap 'rm -rf "$simulation_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$simulation_dir"
ghdl -a --std=08 \
  "$project_dir/Exponentiation/source/modular_multiplication.vhd" \
  "$project_dir/Exponentiation/source/exponentiation.vhd" \
  "$project_dir/RSA_accelerator/source/rsa_core.vhd" \
  "$testbench_dir/rsa_core_multicore_tb.vhd"
ghdl -e --std=08 rsa_core_multicore_tb
ghdl -r --std=08 rsa_core_multicore_tb \
  "-gINPUT_FILE=$project_dir/Exponentiation/testbench/course_vectors/ct4_in.hex" \
  "-gEXPECTED_FILE=$project_dir/Exponentiation/testbench/course_vectors/pt4_expected.hex" \
  "$@" --assert-level=error --unbuffered
