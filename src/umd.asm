; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; uMD: a PS/2 mouse driver for DOS.
;
; UMD.COM stays resident with its PSP, the code in resident.asm and
; cursor.asm, and the data that follows the code. The installer in
; install.asm is released after the TSR call.

cpu 286
bits 16
org 100h

%include "version.inc"

start:
    jmp install

%include "resident.asm"
%include "cursor.asm"
resident_end:

%include "install.asm"
