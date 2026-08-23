# CP/M Disk Cleaner

`FDCLEAN.COM` is a CP/M transient program that cleans floppy-drive heads by moving the head in a zig-zag seek pattern while a cleaning disk is installed.

The motion pattern is modelled on Greaseweazle's `gw clean` command: divide the cylinder range into roughly eight bands, seek to the far end of each band, pause briefly, then seek back to the near end and pause again. Greaseweazle defaults to three passes and a 100 ms linger at each stop.

The first backend targets the **Altair FDC+ Drive Type 8 / iCOM 3712-compatible interface** used in the IMSAI CP/M 3 system.

## Safety

The cleaner issues only configure/select/restore/set-track/seek/clear-error commands. It contains **no sector READ or WRITE commands** and does not transfer disk data.

It also deliberately does **not** reset the FDC+ controller. Since the utility runs underneath CP/M, resetting the controller directly could invalidate state maintained by the CP/M BIOS for another floppy drive. Instead, FDCLEAN restores only the selected physical drive to track 0 and performs explicit seeks from there.

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
```

The optional pass count is `1..9`; the default is 3.

For 77 cylinders, the Greaseweazle-style step is `77 / 8 = 9`, producing this sequence per pass:

```text
8 0 17 9 26 18 35 27 44 36 53 45 62 54 71 63 76 72
```

The utility restores the selected drive to track 0 when the run completes or after a seek error.

## Build on Ubuntu

Pasmo is available in Ubuntu's package repositories:

```sh
sudo apt install pasmo
make
```

The result is:

```text
dist/FDCLEAN.COM
```

Pasmo's raw-binary mode can directly create a CP/M `.COM` file when the source begins at `ORG 100H`.

## Project status

The initial version is deliberately controller-specific so it can issue genuine seek commands without trying to read an unformatted cleaning disk. A future version can add additional controller backends while keeping the same user interface and cleaning pattern.
