; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; BIOS PS/2 device handler. The BIOS pushes status, X, Y, and Z words and
; makes a far call. The handler runs on the stack of the interrupted program
; with interrupts disabled, so that a second packet cannot interrupt a draw.

ps2_handler:
    cli
    pusha
    push ds
    push es
    mov bp, sp
    mov ax, [bp+30]         ; status
    mov bx, [bp+28]         ; X
    mov cx, [bp+26]         ; Y
    push cs
    pop ds
    call process_packet
    pop es
    pop ds
    popa
    retf
