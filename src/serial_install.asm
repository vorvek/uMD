; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Transient serial part: find the COM port and the mouse, program the UART,
; and hook the interrupt. DOS releases this part after the TSR call.

; Select the port and the protocol and set the line parameters. CF set when
; no mouse answers and no protocol option was given.
serial_attach:
    mov si, [opt_port]
    test si, si
    jnz .one
    inc si
.scan:                          ; the first port with a mouse
    call probe
    jnc .found
    inc si
    cmp si, 4
    jbe .scan
    cmp byte [opt_proto], -1
    je .none
    mov si, 1
.present:                       ; no answer: the first port that exists
    call port_base
    jnz .one
    inc si
    cmp si, 4
    jbe .present
.none:
    stc
    ret
.one:
    call probe
    jnc .found
    cmp word [uart], 0
    je .none
    cmp byte [opt_proto], -1
    je .none
.found:
    mov al, [opt_proto]
    cmp al, -1
    jne .proto
    mov al, [found_proto]
.proto:
    mov [proto], al
    mov dx, [uart]
    add dx, 3                   ; line control: 7N1, or 8N1 for Mouse Systems
    mov al, 2
    cmp byte [proto], PROTO_MSYS
    jne .lcr
    inc al
.lcr:
    out dx, al
    mov al, [opt_irq]
    test al, al
    jnz .irq
    mov al, 4                   ; COM1 and COM3 use IRQ 4, COM2 and COM4 IRQ 3
    test si, 1
    jnz .irq
    dec al
.irq:
    mov [irq], al
    add al, '0'
    mov [msg_irq], al
    mov ax, si
    add al, '0'
    mov [msg_com], al
    clc
    ret

; SI = port 1 to 4. DX = UART base from the BIOS data area, 0 when the port
; does not exist. ES = BIOS data segment.
port_base:
    mov ax, 40h
    mov es, ax
    mov bx, si
    dec bx
    shl bx, 1
    mov dx, [es:bx]
    mov [uart], dx
    test dx, dx
    ret

; SI = port 1 to 4. Set 1200 baud, 7N1, power the mouse off and on, and
; wait for the identification bytes. CF set when no mouse answers.
probe:
    call port_base
    jz .none
    inc dx                      ; interrupt enable: off
    mov al, 0
    out dx, al
    inc dx                      ; FIFO control: off
    out dx, al
    inc dx                      ; line control: divisor latch
    mov al, 80h
    out dx, al
    sub dx, 3
    mov ax, 96                  ; 1200 baud
    out dx, al
    inc dx
    mov al, ah
    out dx, al
    add dx, 2                   ; line control: 7N1
    mov al, 2
    out dx, al
    inc dx                      ; modem control: DTR and RTS low
    mov al, 0
    out dx, al
    mov cx, 16                  ; two quiet ticks with the power off, or
.quiet:                         ; 16 stray bytes
    mov bl, 2
    call recv
    jc .power
    loop .quiet
.power:
    mov dx, [uart]
    add dx, 4                   ; modem control: DTR and RTS high
    mov al, 3
    out dx, al
    mov bl, 3
    call recv
    jc .none
    cmp al, 'M'
    jne .none
    mov byte [found_proto], PROTO_MS
    mov bl, 2
    call recv
    jc .found
    cmp al, '3'
    jne .found
    mov byte [found_proto], PROTO_LT
.found:
    clc
    ret
.none:
    stc
    ret

; Wait up to BL timer ticks for a byte from the UART. AL = byte, or CF set.
; ES = BIOS data segment.
recv:
    mov ah, [es:6Ch]
.poll:
    mov dx, [uart]
    add dx, 5
    in al, dx
    test al, 1
    jnz .byte
    cmp ah, [es:6Ch]
    je .poll
    mov ah, [es:6Ch]
    dec bl
    jnz .poll
    stc
    ret
.byte:
    sub dx, 5
    in al, dx
    clc
    ret

; Hook the interrupt vector, unmask the IRQ, and let the UART interrupt.
serial_enable:
    mov al, [irq]
    add al, 8
    mov ah, 35h
    int 21h
    mov [old_irq], bx
    mov [old_irq+2], es
    mov al, [irq]
    add al, 8
    mov ah, 25h
    mov dx, serial_isr
    int 21h
    mov cl, [irq]
    mov ah, 1
    shl ah, cl
    in al, 21h
    mov [pic_saved], al
    not ah
    and al, ah
    out 21h, al
    mov dx, [uart]
    in al, dx                   ; drop a stale byte
    inc dx                      ; interrupt enable: received data
    mov al, 1
    out dx, al
    add dx, 3                   ; modem control: DTR, RTS, and OUT2 high
    mov al, 0Bh
    out dx, al
    ret

; Stop the UART interrupt, mask the IRQ again if it was masked, and put the
; old vector back. ES = resident segment.
serial_detach:
    mov dx, [es:uart]
    inc dx                      ; interrupt enable: off
    mov al, 0
    out dx, al
    add dx, 3                   ; modem control: power off
    out dx, al
    mov cl, [es:irq]
    mov ah, 1
    shl ah, cl
    in al, 21h
    test [es:pic_saved], ah
    jz .vector
    or al, ah
    out 21h, al
.vector:
    mov al, [es:irq]
    add al, 8
    mov ah, 25h
    lds dx, [es:old_irq]
    int 21h
    push cs
    pop ds
    ret

; One decimal digit at SI. AX = value, CF set when there is none.
digit:
    lodsb
    sub al, '0'
    cmp al, 9
    ja .bad
    mov ah, 0
    clc
    ret
.bad:
    stc
    ret

opt_port    dw 0                ; 0: the first port with a mouse
opt_irq     db 0                ; 0: the default IRQ of the port
opt_proto   db -1               ; -1: from the probe
found_proto db PROTO_MS
