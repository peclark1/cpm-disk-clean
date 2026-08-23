#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: verify_build.py FDCLEAN.COM FDCLEAN.ASM")

com = Path(sys.argv[1])
src = Path(sys.argv[2])

data = com.read_bytes()
text = src.read_text(encoding="utf-8").upper()

if len(data) < 256:
    raise SystemExit(f"FDCLEAN.COM is unexpectedly small: {len(data)} bytes")

# Program starts at CP/M transient-program address 0100h with LD SP,nn.
if data[0] != 0x31:
    raise SystemExit(f"unexpected first opcode: {data[0]:02X}, expected 31 (LD SP,nn)")

banner = b"FDCLEAN 0.3.1 - Altair FDC+ 3712 head cleaner"
if banner not in data:
    raise SystemExit("compiled banner string not found in FDCLEAN.COM")

# The cleaner must never grow sector data-transfer commands, and it must not
# reset the controller behind CP/M's BIOS.
for forbidden in (
    "C_READ", "C_WRITE", "C_RDBUF", "C_WRTBUF", "C_RDCRC", "C_RESET"
):
    if forbidden in text:
        raise SystemExit(f"forbidden controller command present in source: {forbidden}")

required = (
    "C_SEEK", "C_REST", "C_SETTR", "C_DRVSC", "C_LDCFG", "SPEEDDIV"
)
for name in required:
    if name not in text:
        raise SystemExit(f"required cleaner feature missing from source: {name}")

# Regression guard: the 0.3 experiment inserted a LINGER immediately after
# INITDRV/RESTORE and real FDC+ hardware then reported seek error 08h on both
# physical units. Speed-controlled linger must occur only after a successful
# cleaning seek.
init_to_pass = text.split("CALL    INITDRV", 1)[1].split("PASSLP:", 1)[0]
if "CALL    LINGER" in init_to_pass:
    raise SystemExit("regression: linger present between initial restore and first seek")

print(f"FDCLEAN.COM sanity checks passed ({len(data)} bytes)")
