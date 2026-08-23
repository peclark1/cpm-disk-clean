# Testing FDCLEAN

## Automated build test

Run:

```sh
make test
```

This assembles `src/FDCLEAN.ASM` with Pasmo, verifies that a non-empty CP/M COM file was produced, checks the expected startup opcode and banner, and rejects source that introduces sector data-transfer command names.

## First hardware test

For the safest first test, use a cleaning disk and physical unit notation rather than a CP/M drive alias:

```text
FDCLEAN 0 1
```

Expected behavior:

1. The FDC+ resets and restores unit 0 to track 0.
2. One cleaning pass prints and seeks this sequence:

```text
8 0 17 9 26 18 35 27 44 36 53 45 62 54 71 63 76 72
```

3. The drive returns to track 0.
4. The program returns to CP/M.

After the one-pass test succeeds, the normal default is:

```text
FDCLEAN 0
```

which runs three passes.

## Error test

Running against an unavailable or not-ready drive should terminate with an FDC status error rather than hanging indefinitely. The controller wait loop is bounded.

## Important limitation

The automated test validates assembly and static safety properties; it cannot validate physical head movement. Final validation therefore requires the real FDC+ and drive.
