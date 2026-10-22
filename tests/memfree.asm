; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
; Print the free DOS memory and the largest block in paragraphs.
bits 16
org 100h
    mov sp, end_code+256
    mov bx, (end_code-$$+100h+256+15)/16
    mov ah, 4ah
    int 21h
    mov ah, 52h
    int 21h
    mov ax, [es:bx-2]
    xor dx, dx
    xor bp, bp
.next:
    cmp ax, 0a000h
    jae .print
    mov es, ax
    mov bx, [es:3]
    cmp word [es:1], 0
    jne .used
    add dx, bx
    cmp bx, bp
    jbe .used
    mov bp, bx
.used:
    cmp byte [es:0], 'Z'
    je .print
    add ax, bx
    inc ax
    jmp .next
.print:
    push cs
    pop es
    mov ax, dx
    mov di, total
    call hexword
    mov ax, bp
    mov di, largest
    call hexword
    mov dx, message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
hexword:
    mov cx, 4
.digit:
    rol ax, 4
    mov bx, ax
    and bx, 15
    mov bl, [digits+bx]
    mov [di], bl
    inc di
    loop .digit
    ret
digits db '0123456789ABCDEF'
message db 'FREE '
total db '0000'
    db ' LARGEST '
largest db '0000',13,10,'$'
end_code:
