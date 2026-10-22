; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Transient installer. DOS releases this part after the TSR call.

install:
    mov si, 81h
    call parse_options
    jc .bad_option
    cmp byte [opt_help], 0
    jne .help
    mov ax, 3533h
    int 21h
    mov [old33], bx
    mov [old33+2], es
    mov ax, es
    or ax, bx
    jz .fresh
    cmp word [es:bx+2], 'uM'
    jne .foreign
    cmp word [es:bx+4], 'D'
    jne .foreign
    push es
    push bx
    mov ax, 24h
    int 33h
    pop bx
    pop es
    cmp ch, DRIVER_TYPE     ; the other uMD binary is another driver
    jne .other
    cmp byte [opt_unload], 0
    jne unload
    call apply_scale
    mov dx, msg_present
    jc .status
    mov ax, 1Bh
    int 33h
    mov ax, 1Ah
    int 33h
    mov dx, msg_changed
.status:
    call print_status
    jmp exit_ok
.foreign:
    cmp byte [es:bx], 0CFh
    je .fresh
    xor ax, ax
    int 33h
    cmp ax, 0FFFFh
    jne .fresh
.other:
    mov dx, msg_other
    jmp exit_error
.fresh:
    cmp byte [opt_unload], 0
    jne .absent
%ifdef SERIAL
    call serial_attach
    jc .no_mouse
    call apply_scale
    call reset_state
    call serial_enable
%else
    mov ax, 0C205h
    mov bh, 3               ; three-byte packets
    int 15h
    jc .no_mouse
    mov ax, 0C203h
    mov bh, 3               ; 8 counts per millimeter
    int 15h
    push cs
    pop es
    mov bx, ps2_handler
    mov ax, 0C207h
    int 15h
    jc .no_mouse
    call apply_scale
    call reset_state
    mov ax, 0C200h
    mov bh, 1
    int 15h
    jc .unregister
%endif
    mov ax, 3510h
    int 21h
    mov [old10], bx
    mov [old10+2], es
    mov ax, 2533h
    mov dx, int33
    int 21h
    mov ax, 2510h
    mov dx, int10
    int 21h
    push cs
    pop es
    mov dx, msg_installed
    call print_status
    mov es, [2Ch]
    mov ah, 49h
    int 21h
    mov word [2Ch], 0
    mov dx, (resident_end-$$+100h+15)/16
    mov ax, 3100h
    int 21h
%ifndef SERIAL
.unregister:
    xor bx, bx
    mov es, bx
    mov ax, 0C207h
    int 15h
%endif
.no_mouse:
    mov dx, msg_no_mouse
    jmp exit_error
.absent:
    mov dx, msg_absent
    jmp exit_error
.bad_option:
    mov dx, msg_option
    jmp exit_error
.help:
    mov dx, msg_help
    call print
exit_ok:
    mov ax, 4C00h
    int 21h

exit_error:
    call print
    mov ax, 4C01h
    int 21h

; ES = resident segment.
unload:
    mov di, es
    mov ax, 3510h
    int 21h
    cmp bx, int10
    jne .busy
    mov ax, es
    cmp ax, di
    jne .busy
%ifdef SERIAL
    mov al, [es:irq]
    add al, 8
    mov ah, 35h
    int 21h
    cmp bx, serial_isr
    jne .busy
    mov ax, es
    cmp ax, di
    jne .busy
    call serial_detach
%else
    mov ax, 0C200h
    mov bh, 0
    int 15h
    xor bx, bx
    mov es, bx
    mov ax, 0C207h
    int 15h
%endif
    mov es, di
    mov dx, [es:old10]
    mov ds, [es:old10+2]
    mov ax, 2510h
    int 21h
    mov dx, [es:old33]
    mov ds, [es:old33+2]
    mov ax, 2533h
    int 21h
    push cs
    pop ds
    mov ah, 49h
    int 21h
    mov dx, msg_removed
    call print
    jmp exit_ok
.busy:
    mov dx, msg_busy
    jmp exit_error

; Write the /X and /Y percentages to the resident scale in ES.
; CF set when no sensitivity option was given.
apply_scale:
    mov ax, [opt_x]
    test ax, ax
    jz .y
    call to_scale
    mov [es:scale_x], ax
.y:
    mov ax, [opt_y]
    test ax, ax
    jz .done
    call to_scale
    mov [es:scale_y], ax
.done:
    mov ax, [opt_x]
    or ax, [opt_y]
    jnz .given
    stc
    ret
.given:
    clc
    ret

; AX percent to 8.8 fixed point.
to_scale:
    mov bx, 256
    mul bx
    mov bx, 100
    div bx
    ret

; Print the message in DX and the sensitivities of the driver in ES.
print_status:
    call print
    mov dx, msg_x
    call print
    mov ax, [es:scale_x]
    call print_percent
    mov dx, msg_y
    call print
    mov ax, [es:scale_y]
    call print_percent
    mov dx, msg_end
print:
    mov ah, 9
    int 21h
    ret

; AX 8.8 fixed point to a decimal percentage.
print_percent:
    mov bx, 100
    mul bx
    add ax, 128
    adc dx, 0
    mov bx, 256
    div bx
    mov bx, 10
    xor cx, cx
.digit:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .digit
.out:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop .out
    ret

; Command tail at SI. CF set on an invalid option.
parse_options:
    lodsb
    cmp al, 13
    je .done
    cmp al, ' '
    jbe parse_options
    cmp al, '/'
    je .option
    cmp al, '-'
    jne .bad
.option:
    lodsb
    cmp al, '?'
    je .help
%ifdef SERIAL
    cmp al, '3'
    je .logitech
%endif
    and al, 0DFh
    cmp al, 'U'
    je .unload
    cmp al, 'X'
    je .x
    cmp al, 'Y'
    je .y
%ifdef SERIAL
    cmp al, 'C'
    je .port
    cmp al, 'I'
    je .irq
    cmp al, 'M'
    je .microsoft
    cmp al, 'Z'
    je .msystems
%endif
    cmp al, 'S'
    jne .bad
    call number
    jc .bad
    mov [opt_y], ax
    jmp .store_x
.x:
    call number
    jc .bad
.store_x:
    mov [opt_x], ax
    jmp parse_options
.y:
    call number
    jc .bad
    mov [opt_y], ax
    jmp parse_options
.unload:
    mov byte [opt_unload], 1
    jmp parse_options
.help:
    mov byte [opt_help], 1
    jmp parse_options
%ifdef SERIAL
.port:
    call digit
    jc .bad
    cmp al, 1
    jb .bad
    cmp al, 4
    ja .bad
    mov [opt_port], ax
    jmp parse_options
.irq:
    call digit
    jc .bad
    cmp al, 2
    jb .bad
    cmp al, 7
    ja .bad
    mov [opt_irq], al
    jmp parse_options
.microsoft:
    mov al, PROTO_MS
    jmp .protocol
.logitech:
    mov al, PROTO_LT
    jmp .protocol
.msystems:
    mov al, PROTO_MSYS
.protocol:
    mov [opt_proto], al
    jmp parse_options
%endif
.done:
    clc
    ret
.bad:
    stc
    ret

; Decimal number at SI, 10 to 400. CF set when invalid.
number:
    xor ax, ax
.digit:
    mov bl, [si]
    sub bl, '0'
    cmp bl, 9
    ja .end
    inc si
    mov bh, 0
    mov dx, 10
    mul dx
    add ax, bx
    cmp ax, 1000
    jae .bad
    jmp .digit
.end:
    cmp ax, 10
    jb .bad
    cmp ax, 400
    ja .bad
    clc
    ret
.bad:
    stc
    ret

opt_x      dw 0
opt_y      dw 0
opt_unload db 0
opt_help   db 0

%ifdef SERIAL
%define PROG 'UMDCOM'
msg_installed db 'uMD ', UMD_VERSION, ' installed on COM'
msg_com       db '1, IRQ '
msg_irq       db '4.$'
%else
%define PROG 'UMD'
msg_installed db 'uMD ', UMD_VERSION, ' installed.$'
%endif
msg_present   db 'uMD is already installed.$'
msg_changed   db 'uMD sensitivity changed.$'
msg_x         db ' X $'
msg_y         db '%, Y $'
msg_end       db '%.', 13, 10, '$'
msg_removed   db 'uMD removed.', 13, 10, '$'
msg_other     db 'Another mouse driver is installed.', 13, 10, '$'
%ifdef SERIAL
msg_no_mouse  db 'No serial mouse found.', 13, 10, '$'
%else
msg_no_mouse  db 'No PS/2 mouse found.', 13, 10, '$'
%endif
msg_absent    db 'uMD is not installed.', 13, 10, '$'
msg_busy      db 'Cannot remove uMD. The interrupt vectors have changed.', 13, 10, '$'
msg_option    db 'Invalid option. Run ', PROG, ' /? for help.', 13, 10, '$'
msg_help:
%ifdef SERIAL
    db 'uMD ', UMD_VERSION, ', a serial mouse driver for DOS.', 13, 10
    db 'Copyright (C) 2026 Vorvek (github.com/vorvek). GPL-3.0-only. No warranty.', 13, 10, 13, 10
    db 'UMDCOM [/C<n>] [/I<n>] [/M | /3 | /Z] [/X<n>] [/Y<n>] [/S<n>] [/U]', 13, 10, 13, 10
    db '  /C<n>  Use COM port n (1 to 4). Default: the first port with a mouse.', 13, 10
    db '  /I<n>  Use IRQ n (2 to 7). Default: 4 for COM1 and COM3, 3 for COM2 and COM4.', 13, 10
    db '  /M     Use the Microsoft protocol, two buttons.', 13, 10
    db '  /3     Use the Logitech protocol, three buttons.', 13, 10
    db '  /Z     Use the Mouse Systems protocol, three buttons.', 13, 10
    db '  /X<n>  Set the horizontal sensitivity to n percent (10 to 400).', 13, 10
    db '  /Y<n>  Set the vertical sensitivity to n percent.', 13, 10
    db '  /S<n>  Set both sensitivities.', 13, 10
    db '  /U     Remove uMD from memory.', 13, 10, 13, 10
    db 'Without /M, /3, or /Z, the driver finds the protocol from the mouse.', 13, 10
    db 'Run UMDCOM with /X, /Y, or /S again to change the installed driver.', 13, 10, '$'

%include "serial_install.asm"
%else
    db 'uMD ', UMD_VERSION, ', a PS/2 mouse driver for DOS.', 13, 10
    db 'Copyright (C) 2026 Vorvek (github.com/vorvek). GPL-3.0-only. No warranty.', 13, 10, 13, 10
    db 'UMD [/X<n>] [/Y<n>] [/S<n>] [/U]', 13, 10, 13, 10
    db '  /X<n>  Set the horizontal sensitivity to n percent (10 to 400).', 13, 10
    db '  /Y<n>  Set the vertical sensitivity to n percent.', 13, 10
    db '  /S<n>  Set both sensitivities.', 13, 10
    db '  /U     Remove uMD from memory.', 13, 10, 13, 10
    db 'Run UMD with /X, /Y, or /S again to change the installed driver.', 13, 10, '$'
%endif
