# CP/M Disk Cleaner

`FDCLEAN.COM` is a CP/M transient program that cleans floppy-drive heads by moving the head in a zig-zag seek pattern while a cleaning disk is installed.

The motion pattern is modelled on Greaseweazle's `gw clean` command: divide the cylinder range into roughly eight bands, seek to the far end of each band, pause briefly, then seek back to the near end and pause again. Greaseweazle defaults to three passes and a 100 ms linger at each stop.

The current backend targets the **Altair FDC+ Drive Type 8 / iCOM 3712-compatible interface** used in the IMSAI CP/M 3 system.

## Safety and CP/M handoff

FDCLEAN contains **no sector READ or WRITE commands** and performs no disk data transfer. It uses only controller reset, configure, select, restore, set-track, seek, and clear-error operations.

Physical testing established that direct 3712 seek commands must begin from a deterministic controller state. FDCLEAN therefore resets the FDC+ 3712 emulation on entry, restores the requested drive to track 0, and then performs the cleaning sweep.

Before returning to CP/M, FDCLEAN resets the controller again, restores **both physical floppy units** to track 0, clears residual controller error state, reselects the requested unit, and leaves the command port in examine-status mode. This handoff was validated on the physical IMSAI: CP/M 3 floppy access continues to work immediately after FDCLEAN exits.

Use a proper wet or dry head-cleaning disk according to its instructions.

## Current hardware assumptions

- Altair FDC+ Drive Type 8 / iCOM 3712-compatible command interface
- command/status port `08h`
- data-output port `09h`
- 77-cylinder 8-inch drive, tracks `0..76`
- physical units `0` and `1`
- current CP/M 3 aliases: `C:` -> unit 0, `D:` -> unit 1

## Usage

```text
FDCLEAN 0
FDCLEAN 1
FDCLEAN C:
FDCLEAN D:
FDCLEAN C: 5
FDCLEAN 0 3 2
```

The first optional argument is the pass count, `1..9`; the default is 3.

The second optional argument is a **speed divisor**, `1..4`:

- `1` = normal speed, about 100 ms linger between seeks (default)
- `2` = about half speed, about 200 ms linger
- `3` = about one-third speed, about 300 ms linger
- `4` = about one-quarter speed, about 400 ms linger

For example, this runs three passes at approximately half speed:

```text
FDCLEAN 0 3 2
```

The speed divisor increases the settling time after each completed seek before the next seek command. Physical testing confirmed that this provides an effective slower cleaning cycle for the slower of the two target drives.

For 77 cylinders, the Greaseweazle-style step is `77 / 8 = 9`, producing this sequence per pass:

```text
8 0 17 9 26 18 35 27 44 36 53 45 62 54 71 63 76 72
```

## Build on Ubuntu

Pasmo is available in Ubuntu's package repositories:

```sh
sudo apt install pasmo
make test
```

The generated CP/M transient program is:

```text
dist/FDCLEAN.COM
```

`make test` builds the program and runs static safety checks against both the source and compiled binary.

## Hardware validation

Version 0.4 was validated on the physical IMSAI with the Altair FDC+ in Drive Type 8 mode. Testing confirmed:

- the cleaning sweep completes correctly
- speed divisors provide useful slower cleaning speeds
- both physical floppy units are restored during controller handoff
- CP/M 3 can access the floppy drives immediately after FDCLEAN returns

## Project status

**FDCLEAN 0.4** is the current hardware-validated release for the Altair FDC+ Drive Type 8 / iCOM 3712-compatible backend.
