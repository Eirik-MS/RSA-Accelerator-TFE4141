"""Convert course case 4 to VHDL hex, verifying the software reference first."""
import argparse
from pathlib import Path
import zipfile

N = 0x99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d
D = 0x0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    prefix = "files_for_the_pynq_sd_card/crypto/rsa/"
    with zipfile.ZipFile(args.archive) as archive:
        ciphertext = archive.read(prefix + "inp_messages/ct4_in.txt")
        reference = archive.read(prefix + "otp_sw_messages/pt4_out.txt")
    if len(ciphertext) != 882 * 32 or len(reference) != len(ciphertext):
        raise ValueError("Course case 4 must contain exactly 882 complete 32-byte blocks")
    inputs = [int.from_bytes(ciphertext[i:i+32], "little")
              for i in range(0, len(ciphertext), 32)]
    expected = [pow(value, D, N) for value in inputs]
    if any(value >= N for value in inputs):
        raise ValueError("Ciphertext block is outside the RSA modulus")
    calculated = b"".join(value.to_bytes(32, "little") for value in expected)
    if calculated != reference:
        raise ValueError("Python pow results do not match the supplied software reference")
    output_dir = Path(__file__).resolve().parent / "course_vectors"
    output_dir.mkdir(exist_ok=True)
    for name, values in [("ct4_in.hex", inputs), ("pt4_expected.hex", expected)]:
        (output_dir / name).write_text(
            "".join(f"{value:064X}\n" for value in values), encoding="ascii")
    print("Generated 882 input/expected pairs; all agree with the course software reference.")


if __name__ == "__main__":
    main()
