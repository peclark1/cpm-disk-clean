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

if data[0] != 0x31:
    raise SystemExit(f"unexpected first opcode: {data[0]:02X}, expected 31 (LD SP,nn)")

banner = b"FDCLEAN 0.4D - FDC+3712 reset/handoff diagnostic"
if banner not in data:
    raise SystemExit("compiled diagnostic banner string not found in FDCLEAN.COM")

# Cleaning media must never be read or written. Controller RESET is explicitly
# allowed in this diagnostic because we are testing deterministic ownership
# handoff between FDCLEAN and the CP/M 3 BIOS.
for forbidden in (
    "C_READ", "C_WRITE", "C_RDBUF", "C_WRTBUF", "C_RDCRC"
):
    if forbidden in text:
        raise SystemExit(f"forbidden controller command present in source: {forbidden}")

required = (
    "C_SEEK", "C_REST", "C_SETTR", "C_DRVSC", "C_LDCFG", "C_RESET",
    "SPEEDDIV", "RESETCTL:", "HANDOFF:", "SAVEUNIT", "HANDERR"
)
for name in required:
    if name not in text:
        raise SystemExit(f"required diagnostic feature missing from source: {name}")

init = text.split("INITDRV:", 1)[1].split("RESETCTL:", 1)[0]
if "CALL    RESETCTL" not in init or "CALL    RESTORE" not in init:
    raise SystemExit("INITDRV must reset the controller and restore the selected unit")
if init.index("CALL    RESETCTL") > init.index("CALL    RESTORE"):
    raise SystemExit("INITDRV restore occurs before controller reset")

handoff = text.split("HANDOFF:", 1)[1].split("DOCMD:", 1)[0]
if "CALL    RESETCTL" not in handoff:
    raise SystemExit("HANDOFF must reset the controller")
if handoff.count("CALL    RESTORE") < 2:
    raise SystemExit("HANDOFF must restore both physical units")

print(f"FDCLEAN.COM diagnostic sanity checks passed ({len(data)} bytes)")
