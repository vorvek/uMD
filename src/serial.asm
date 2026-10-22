; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Resident serial part: the COM port interrupt handler and the packet
; decoders. UMDCOM.COM assembles this file in place of ps2.asm.

PROTO_MS   equ 0        ; Microsoft: three bytes, 7N1
PROTO_LT   equ 1        ; Logitech: Microsoft plus a fourth byte for the middle button
PROTO_MSYS equ 2        ; Mouse Systems: five bytes, 8N1

; The handler runs with interrupts disabled on the stack of the interrupted
; program, like the PS/2 handler, and takes every byte that the UART holds.
serial_isr:
    pusha
    push ds
    push es
    push cs
    pop ds
.next:
    mov dx, [uart]
    add dx, 5               ; line status
    in al, dx
    test al, 1
    jz .done
    sub dx, 5
    in al, dx
    call serial_byte
    jmp .next
.done:
    mov al, 20h
    out 20h, al             ; end of interrupt to the master PIC
    pop es
    pop ds
    popa
    iret

; AL = received byte. A complete packet goes to process_packet in the PS/2
; convention: AL buttons and sign bits, BL X count, CL Y count, Y positive
; upward.
serial_byte:
    mov si, [scount]
    cmp byte [proto], PROTO_MSYS
    je .msys
    test al, 40h            ; the first byte has bit 6 set
    jz .data
    xor si, si
    jmp .store
.data:
    test si, si
    jnz .store
    cmp byte [proto], PROTO_LT
    jne .ret
    shr al, 3               ; fourth byte: bit 5 is the middle button
    and al, 4
    mov [middle], al
    xor cx, cx              ; no motion
    jmp .ms_buttons
.msys:
    test si, si
    jnz .store
    mov ah, al
    and ah, 0F8h
    cmp ah, 80h             ; the first byte is 10000lmr
    jne .ret
.store:
    mov [spacket+si], al
    inc si
    mov [scount], si
    cmp si, 3
    jb .ret
    cmp byte [proto], PROTO_MSYS
    je .msys_pair
    mov word [scount], 0
    mov ah, [spacket]       ; data bytes have bits 7 and 6 clear
    mov ch, ah
    shl ch, 6
    or ch, [spacket+1]      ; X: bits 1 and 0 of the first byte, then six bits
    mov cl, ah
    shl cl, 4
    and cl, 0C0h
    or cl, [spacket+2]      ; Y: bits 3 and 2 of the first byte, then six bits
    neg cl                  ; Microsoft counts down as positive
.ms_buttons:                ; CH = X, CL = Y
    mov al, [spacket]
    shr al, 4
    and al, 3               ; L, R
    mov bx, ms_buttons
    xlat
    or al, [middle]
    mov bl, ch
    jmp .report
.msys_pair:                 ; bytes 2 and 3 after the third byte, bytes 4 and
    cmp si, 3               ; 5 after the fifth
    je .pair
    cmp si, 5
    jb .ret
    mov word [scount], 0
.pair:
    mov al, [spacket]
    not al
    and al, 7               ; L, M, R, 1 when pressed
    mov bx, msys_buttons
    xlat
    mov bl, [spacket+si-2]
    mov cl, [spacket+si-1]
.report:
    test bl, bl
    jns .x
    or al, 10h
.x:
    test cl, cl
    jns .y
    or al, 20h
.y:
    jmp process_packet
.ret:
    ret

; Microsoft L, R bits and Mouse Systems L, M, R bits to the INT 33h order
; L, R, M.
ms_buttons   db 0, 2, 1, 3
msys_buttons db 0, 2, 4, 6, 1, 3, 5, 7

uart      dw 0
irq       db 0
pic_saved db 0          ; interrupt mask before the installation
old_irq   dd 0
proto     db 0
middle    db 0
scount    dw 0
spacket   times 5 db 0
