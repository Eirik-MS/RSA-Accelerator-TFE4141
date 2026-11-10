"""Short arithmetic and wrapper checks; all build outputs stay in a temporary folder."""
from pathlib import Path
import random
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    rng = random.Random(4141)
    vectors = []
    for n in [1, 2, 3, 33, 2**128-1, 2**255, 2**256-1]:
        for a in sorted({0, 1 % n, n-1}):
            for b in [0, 1, n-1, 2**256-1]:
                vectors.append((a, b, n))
    for _ in range(96):
        n = rng.randrange(1, 2**256)
        vectors.append((rng.randrange(n), rng.getrandbits(256), n))
    with tempfile.TemporaryDirectory(prefix="rsa-timing-check-") as build:
        work = Path(build)
        (work / "modmult_vectors.txt").write_text("".join(
            f"{a:064X} {b:064X} {n:064X} {(a*b)%n:064X}\n" for a, b, n in vectors),
            encoding="ascii")
        sources = [
            "Exponentiation/source/modular_multiplication.vhd",
            "Exponentiation/source/exponentiation.vhd",
            "RSA_accelerator/source/rsa_core.vhd",
            "Exponentiation/testbench/modmult_regression_tb.vhd",
            "Exponentiation/testbench/modmult_tb.vhd",
            "Exponentiation/testbench/exponentiation_tb.vhd",
            "RSA_accelerator/testbench/rsa_core_multicore_tb.vhd",
        ]

        def run(*args):
            subprocess.run(args, cwd=work, check=True)

        run("ghdl", "-a", "--std=08", *(str(root / s) for s in sources))
        tests = [("modmult_regression_tb", []), ("modular_multiplication_tb", []),
                 ("exponentiation_tb", []),
                 ("rsa_core_multicore_tb", ["-gCORE_COUNT=1"]),
                 ("rsa_core_multicore_tb", ["-gCORE_COUNT=2"])]
        for entity, args in tests:
            print("Checking", entity, *args, flush=True)
            run("ghdl", "-e", "--std=08", entity)
            run("ghdl", "-r", "--std=08", entity, *args,
                "--assert-level=error", "--unbuffered")
        with (work / "synthesized.vhd").open("w") as output:
            subprocess.run(["ghdl", "--synth", "--std=08", "rsa_core"],
                           cwd=work, stdout=output, check=True)
        print("ALL SHORT TIMING-CHANGE CHECKS PASSED (including GHDL synthesis).")
        print("Vivado routed timing and the full course run remain separate checks.")


if __name__ == "__main__":
    main()
