;==============================================================================
; FDCLEAN.ASM -- CP/M floppy head cleaning utility
; Altair FDC+ Drive Type 8 / iCOM 3712-compatible backend
; Version 0.3.1, 2026-08-23
;
; Modelled on Greaseweazle "gw clean": move the head in a zig-zag pattern and
; linger briefly at each endpoint while a cleaning disk is installed.
;
; IMPORTANT:
;   * NO sector reads are performed.
;   * NO sector writes are performed.
;   * The program talks directly to FDC+ ports 08H/09H.
;   * It deliberately does NOT reset the controller behind CP/M's BIOS.
;   * Pattern is for 77-cylinder 8-inch drives (tracks 0..76).
;   * Physical unit 0/1 can always be specified directly.
;   * C:/D: are aliases for unit 0/1 in the current IMSAI CP/M 3 system.
;
; Usage:
;       FDCLEAN 0
;       FDCLEAN 1
;       FDCLEAN C:
;       FDCLEAN D:
;       FDCLEAN C: 5       ; optional pass count 1..9, default 3
;       FDCLEAN 0 3 2      ; 3 passes, speed divisor 2 (~half speed)
;
; Speed divisor controls the dwell between seek commands:
;       1 = normal (~100 ms, default)
;       2 = half speed (~200 ms)
;       3 = third speed (~300 ms)
;       4 = quarter speed (~400 ms)
;
; This does not change the FDC+'s internal step-pulse rate. It gives slower
; drive mechanics more settling time before the next seek command.
;
; Greaseweazle algorithm for 77 cylinders:
;   step = max(cylinders / 8, 2) = 9
;   for base = 0,9,18,...72:
;       seek min(base+8,76), linger, seek base, linger
;
; Sequence per pass:
;   8 0 17 9 26 18 35 27 44 36 53 45 62 54 71 63 76 72
;==============================================================================

        ORG     0100H

BDOS    EQU     0005H

; FDC+ 3712 commands used by this utility.
C_SEEK  EQU     09H
C_CLRER EQU     0BH
C_REST  EQU     0DH
C_SETTR EQU     11H
C_LDCFG EQU     15H
C_DRVSC EQU     21H

; Controller status bits used for seek/restore failure detection.
S_BUSY  EQU     01H
S_CRCER EQU     08H
S_NRDY  EQU     20H
S_SEKER EQU     S_CRCER + S_NRDY

; Altair FDC+ Drive Type 8 ports.
CMDOUT  EQU     08H
DATAIN  EQU     08H
DATAOUT EQU     09H

PATLEN  EQU     18

START:
        LD      SP,STACKTOP
        LD      DE,BANNER
        CALL    PSTR

        CALL    PARSE
        OR      A
        JP      NZ,BADUSE

        LD      DE,READYMSG
        CALL    PSTR
        LD      A,(UNIT)
        OR      A
        JR      Z,SHOWU0
        LD      A,'1'
        JR      SHOWUNIT
SHOWU0:
        LD      A,'0'
SHOWUNIT:
        CALL    PCHR
        LD      DE,PASSMSG
        CALL    PSTR
        LD      A,(PASSES)
        CALL    PDEC
        LD      DE,SPEEDMSG
        CALL    PSTR
        LD      A,(SPEEDDIV)
        CALL    PDEC
        CALL    CRLF

        CALL    INITDRV
        OR      A
        JP      NZ,HWFAIL

        ; Important: begin the first seek immediately after RESTORE, matching
        ; the proven 0.2 command sequence. Speed-controlled linger applies
        ; only after successful cleaning seeks.
        LD      A,1
        LD      (PASSNO),A

PASSLP:
        LD      DE,PASSHDR
        CALL    PSTR
        LD      A,(PASSNO)
        CALL    PDEC
        LD      DE,COLONSP
        CALL    PSTR

        LD      HL,PATTERN
        LD      B,PATLEN

TRACKLP:
        LD      A,(HL)
        INC     HL
        LD      (CURTRK),A

        PUSH    BC
        PUSH    HL

        LD      A,(CURTRK)
        CALL    PDEC
        LD      A,' '
        CALL    PCHR

        LD      A,(CURTRK)
        CALL    SEEKTRK
        LD      (SEEKRC),A
        OR      A
        JR      NZ,NOLINGER
        CALL    LINGER
NOLINGER:
        POP     HL
        POP     BC

        LD      A,(SEEKRC)
        OR      A
        JP      NZ,SEEKFAIL

        DJNZ    TRACKLP

        CALL    CRLF

        LD      A,(PASSNO)
        LD      B,A
        LD      A,(PASSES)
        CP      B
        JR      Z,ALLDONE
        LD      A,B
        INC     A
        LD      (PASSNO),A
        JP      PASSLP

ALLDONE:
        ; Return to track zero. A late restore error is reported but does not
        ; turn a completed cleaning sweep into an unsafe state.
        CALL    RESTORE
        OR      A
        JR      Z,DONEOK
        LD      DE,RESTWARN
        CALL    PSTR
        LD      A,(LASTSTAT)
        CALL    PHEX
        CALL    CRLF
DONEOK:
        LD      DE,DONEMSG
        CALL    PSTR
        JP      EXIT

BADUSE:
        LD      DE,USAGE
        CALL    PSTR
        JP      EXIT

SEEKFAIL:
        CALL    CRLF
        LD      DE,SEEKMSG
        CALL    PSTR
        LD      A,(LASTSTAT)
        CALL    PHEX
        CALL    CRLF
        CALL    RESTORE
        JP      EXIT

HWFAIL:
        LD      DE,HWMSG
        CALL    PSTR
        LD      A,(LASTSTAT)
        CALL    PHEX
        CALL    CRLF

EXIT:
        LD      C,0
        CALL    BDOS
        RET

;------------------------------------------------------------------------------
; Parse CCP command tail at 0080H.
; Accepted drive selectors: C:, D:, 0, 1.
; Optional pass count:    1..9 (default 3).
; Optional speed divisor: 1..4 (default 1; 2 is approximately half-speed).
; Returns A=0 success, A=1 syntax error.
;------------------------------------------------------------------------------
PARSE:
        LD      A,3
        LD      (PASSES),A
        LD      A,1
        LD      (SPEEDDIV),A

        LD      A,(0080H)
        LD      B,A
        LD      HL,0081H
        CALL    SKIPSP

        LD      A,B
        OR      A
        JR      Z,PARBAD

        LD      A,(HL)
        INC     HL
        DEC     B

        CP      '0'
        JR      Z,PARU0
        CP      '1'
        JR      Z,PARU1
        AND     05FH
        CP      'C'
        JR      Z,PARU0
        CP      'D'
        JR      Z,PARU1
        JR      PARBAD

PARU0:
        XOR     A
        LD      (UNIT),A
        JR      PARAFTER

PARU1:
        LD      A,1
        LD      (UNIT),A

PARAFTER:
        LD      A,B
        OR      A
        JR      Z,PAROK
        LD      A,(HL)
        CP      ':'
        JR      NZ,PARNCOL
        INC     HL
        DEC     B

PARNCOL:
        CALL    SKIPSP
        LD      A,B
        OR      A
        JR      Z,PAROK

        ; First optional argument: pass count 1..9.
        LD      A,(HL)
        CP      '1'
        JR      C,PARBAD
        CP      ':'             ; ':' is one past '9'
        JR      NC,PARBAD
        SUB     '0'
        LD      (PASSES),A
        INC     HL
        DEC     B

        CALL    SKIPSP
        LD      A,B
        OR      A
        JR      Z,PAROK

        ; Second optional argument: speed divisor 1..4.
        LD      A,(HL)
        CP      '1'
        JR      C,PARBAD
        CP      '5'             ; '5' is one past the accepted range
        JR      NC,PARBAD
        SUB     '0'
        LD      (SPEEDDIV),A
        INC     HL
        DEC     B

        CALL    SKIPSP
        LD      A,B
        OR      A
        JR      NZ,PARBAD

PAROK:
        XOR     A
        RET

PARBAD:
        LD      A,1
        RET

SKIPSP:
        LD      A,B
        OR      A
        RET     Z
        LD      A,(HL)
        CP      ' '
        RET     NZ
        INC     HL
        DEC     B
        JR      SKIPSP

;------------------------------------------------------------------------------
; Prepare the selected drive without resetting the FDC+. CP/M's BIOS owns the
; controller globally, so resetting it here could invalidate the BIOS's state
; for the other physical drive. Loading config/select and restoring only this
; drive gives us a known track-zero reference while keeping the controller up.
;------------------------------------------------------------------------------
INITDRV:
        CALL    SETCFG
        CALL    RESTORE
        RET

SETCFG:
        XOR     A               ; 3712 configuration bits = 0
        OUT     (DATAOUT),A
        LD      A,C_LDCFG
        CALL    OUTCMD
        RET

; Select physical unit 0 or 1 with sector field 1.
; Drive number occupies bits 7-6 in the 3712 drive/sector byte.
SELECT:
        LD      A,(UNIT)
        OR      A
        JR      Z,SEL0
        LD      A,41H           ; unit 1 + sector 1
        JR      SELGO
SEL0:
        LD      A,01H           ; unit 0 + sector 1
SELGO:
        OUT     (DATAOUT),A
        LD      A,C_DRVSC
        CALL    OUTCMD
        RET

RESTORE:
        CALL    SETCFG
        CALL    SELECT
        LD      A,C_REST
        CALL    DOCMD
        LD      (LASTSTAT),A
        AND     S_SEKER
        RET     Z
        LD      A,C_CLRER
        CALL    OUTCMD
        LD      A,1
        RET

;------------------------------------------------------------------------------
; Seek to track in A. No disk read command is ever issued.
;------------------------------------------------------------------------------
SEEKTRK:
        LD      (CURTRK),A
        CALL    SETCFG
        CALL    SELECT
        LD      A,(CURTRK)
        OUT     (DATAOUT),A
        LD      A,C_SETTR
        CALL    OUTCMD
        LD      A,C_SEEK
        CALL    DOCMD
        LD      (LASTSTAT),A
        AND     S_SEKER
        RET     Z
        LD      A,C_CLRER
        CALL    OUTCMD
        LD      A,1
        RET

;------------------------------------------------------------------------------
; Execute command in A and wait for BUSY to clear.
; Uses the same bounded 4 x 16-bit timeout structure as the current CP/M 3
; FDC3712 driver. Returns status in A, FFH on timeout.
;------------------------------------------------------------------------------
DOCMD:
        CALL    OUTCMD
        LD      D,4
TOUTER:
        LD      BC,0
TLOOP:
        IN      A,(DATAIN)
        AND     S_BUSY
        JR      Z,CMDDONE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,TLOOP
        DEC     D
        JR      NZ,TOUTER
        LD      A,0FFH
        RET
CMDDONE:
        IN      A,(DATAIN)
        RET

OUTCMD:
        OUT     (CMDOUT),A
        XOR     A               ; return interface to examine-status mode
        OUT     (CMDOUT),A
        RET

;------------------------------------------------------------------------------
; Base dwell is approximately 100 ms on a 4 MHz Z80.
; Inner loop is about 25 clocks x 2000 x 8 ~= 400,000 clocks.
; SPEEDDIV repeats that base dwell 1..4 times, giving approximately 100, 200,
; 300, or 400 ms between seek commands. This is a mechanical settling delay;
; it does not alter the FDC+'s own step-pulse timing.
;------------------------------------------------------------------------------
LINGER:
        LD      A,(SPEEDDIV)
        LD      E,A
DLSCALE:
        LD      D,8
DL1:
        LD      BC,2000
DL2:
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,DL2
        DEC     D
        JR      NZ,DL1
        DEC     E
        JR      NZ,DLSCALE
        RET

;------------------------------------------------------------------------------
; CP/M console helpers.
;------------------------------------------------------------------------------
PSTR:
        LD      C,9
        CALL    BDOS
        RET

PCHR:
        LD      E,A
        LD      C,2
        CALL    BDOS
        RET

CRLF:
        LD      A,13
        CALL    PCHR
        LD      A,10
        CALL    PCHR
        RET

; Print A as unsigned decimal 0..99.
PDEC:
        LD      (NUMTMP),A
        XOR     A
        LD      (TENSTMP),A
        LD      A,(NUMTMP)
PDIV10:
        CP      10
        JR      C,PDONES
        SUB     10
        LD      (NUMTMP),A
        LD      A,(TENSTMP)
        INC     A
        LD      (TENSTMP),A
        LD      A,(NUMTMP)
        JR      PDIV10
PDONES:
        LD      (ONESTMP),A
        LD      A,(TENSTMP)
        OR      A
        JR      Z,PDNO10
        ADD     A,'0'
        CALL    PCHR
PDNO10:
        LD      A,(ONESTMP)
        ADD     A,'0'
        CALL    PCHR
        RET

; Print A as two hexadecimal digits.
PHEX:
        LD      (HEXTMP),A
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0FH
        CALL    PNIB
        LD      A,(HEXTMP)
        AND     0FH
        CALL    PNIB
        RET

PNIB:
        CP      10
        JR      C,PNDEC
        ADD     A,'A'-10
        JP      PCHR
PNDEC:
        ADD     A,'0'
        JP      PCHR

;------------------------------------------------------------------------------
; Greaseweazle-style 77-cylinder zig-zag pattern.
;------------------------------------------------------------------------------
PATTERN:
        DB      8,0,17,9,26,18,35,27,44
        DB      36,53,45,62,54,71,63,76,72

;------------------------------------------------------------------------------
; Messages and state.
;------------------------------------------------------------------------------
BANNER:
        DB      13,10
        DB      'FDCLEAN 0.3.1 - Altair FDC+ 3712 head cleaner',13,10
        DB      'Greaseweazle-style zig-zag, 77 cylinders, ~100 ms base linger',13,10
        DB      'NO DISK READS OR WRITES ARE PERFORMED.',13,10,'$'

READYMSG:
        DB      'Cleaning FDC+ physical unit ','$'
PASSMSG:
        DB      ', passes ','$'
SPEEDMSG:
        DB      ', speed divisor ','$'
PASSHDR:
        DB      'Pass ','$'
COLONSP:
        DB      ': ','$'
DONEMSG:
        DB      13,10,'Cleaning sweep complete; drive restored to track 0.',13,10,'$'
RESTWARN:
        DB      13,10,'Warning: final restore to track 0 failed. Status=','$'
SEEKMSG:
        DB      'Seek failed. FDC status=','$'
HWMSG:
        DB      'FDC initialization/restore failed. Status=','$'
USAGE:
        DB      13,10,'Usage: FDCLEAN 0  [passes] [speeddiv]',13,10
        DB      '       FDCLEAN 1  [passes] [speeddiv]',13,10
        DB      '       FDCLEAN C: [passes] [speeddiv]',13,10
        DB      '       FDCLEAN D: [passes] [speeddiv]',13,10
        DB      'passes   = 1..9 (default 3)',13,10
        DB      'speeddiv = 1..4 (1 normal, 2 half-speed)',13,10,'$'

UNIT:       DB  0
PASSES:     DB  3
SPEEDDIV:   DB  1
PASSNO:     DB  0
CURTRK:     DB  0
SEEKRC:     DB  0
LASTSTAT:   DB  0
NUMTMP:     DB  0
TENSTMP:    DB  0
ONESTMP:    DB  0
HEXTMP:     DB  0

            DEFS 64
STACKTOP:
