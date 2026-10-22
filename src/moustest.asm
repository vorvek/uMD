; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; MOUSTEST.EXE: check the mouse driver in text mode 03h and VGA mode 13h.
; Shows the pointer, the position, the buttons, the mickeys, and the events
; that the driver reports. With uMD installed, the arrow keys change the
; sensitivity of each axis in the resident driver and the screen shows the
; UMD options that give the same result.

cpu 286
bits 16
org 0

%include "version.inc"

STEP equ 10                     ; percent per key press

start:
    push cs
    pop ds
    push cs
    pop es
    xor ax, ax
    int 33h
    cmp ax, 0FFFFh
    jne .no_driver
    mov ax, 3533h
    int 21h
    cmp word [es:bx+2], 'uM'
    jne .driver
    cmp word [es:bx+4], 'D'
    jne .driver
    mov [umd_seg], es
    add bx, 6
    mov [umd_off], bx
.driver:
    mov ax, 1130h
    mov bh, 3                   ; 8x8 font
    int 10h
    mov [font], bp
    mov [font+2], es
    push cs
    pop es
    call enter_mode
.loop:
    call wait_tick
    call read_driver
    call draw_info
    mov ah, 1
    int 16h
    jz .loop
    mov ah, 0
    int 16h
    cmp ah, 1                   ; Esc
    je .quit
    cmp ah, 32h                 ; M
    je .mode
    cmp ah, 0Fh                 ; Tab
    je .mode
    cmp ah, 13h                 ; R
    je .reset
    cmp ah, 4Bh                 ; Left
    je .x_down
    cmp ah, 4Dh                 ; Right
    je .x_up
    cmp ah, 48h                 ; Up
    je .y_up
    cmp ah, 50h                 ; Down
    je .y_down
    jmp .loop
.mode:
    xor byte [graphics], 1
    call enter_mode
    jmp .loop
.reset:
    xor ax, ax
    mov [events], ax
    mov [total_x], ax
    mov [total_y], ax
    mov [last_dx], ax
    mov [last_dy], ax
    jmp .loop
.x_down:
    mov si, 0
    mov ax, -STEP
    jmp .adjust
.x_up:
    mov si, 0
    mov ax, STEP
    jmp .adjust
.y_down:
    mov si, 2
    mov ax, -STEP
    jmp .adjust
.y_up:
    mov si, 2
    mov ax, STEP
.adjust:
    call adjust
    jmp .loop
.quit:
    mov ax, 0Ch
    xor cx, cx
    int 33h
    mov ax, 3
    int 10h
    xor ax, ax
    int 33h
    cmp word [umd_seg], 0
    je .exit
    mov dx, msg_result
    mov ah, 9
    int 21h
    mov si, 0
    call percent
    call print_number
    mov dx, msg_y
    mov ah, 9
    int 21h
    mov si, 2
    call percent
    call print_number
    mov dx, msg_crlf
    mov ah, 9
    int 21h
.exit:
    mov ax, 4C00h
    int 21h
.no_driver:
    mov dx, msg_no_driver
    mov ah, 9
    int 21h
    mov ax, 4C01h
    int 21h

; Set the video mode, draw the background, reset the driver, and show the
; pointer with the event handler installed.
enter_mode:
    mov ax, 3
    cmp byte [graphics], 0
    je .set
    mov ax, 13h
.set:
    int 10h
    cmp byte [graphics], 0
    je .driver
    push es
    mov ax, 0A000h
    mov es, ax
    xor di, di
    mov dx, 200
.row:
    mov cx, 320
    mov al, 8
    test dl, 15
    jz .line
    mov al, 1
.line:
    stosb
    test cl, 15
    jnz .pixel
    mov byte [es:di-1], 8
.pixel:
    loop .line
    dec dx
    jnz .row
    pop es
.driver:
    xor ax, ax
    int 33h
    mov ax, 0Ch
    mov cx, 0FFh
    mov dx, handler
    int 33h
    mov ax, 1
    int 33h
    ret

; SI = 0 for X or 2 for Y, AX = change in percent.
adjust:
    cmp word [umd_seg], 0
    je .done
    push ax
    call percent
    pop cx
    add ax, cx
    cmp ax, 10
    jge .high
    mov ax, 10
.high:
    cmp ax, 400
    jle .store
    mov ax, 400
.store:
    mov bx, 256
    mul bx
    mov bx, 100
    div bx
    push es
    mov es, [umd_seg]
    mov bx, [umd_off]
    mov [es:bx+si], ax
    pop es
    mov ax, 1Bh
    int 33h
    mov ax, 1Ah
    int 33h
.done:
    ret

; SI = 0 for X or 2 for Y. Returns AX = percent of the resident scale.
percent:
    push es
    mov es, [umd_seg]
    mov bx, [umd_off]
    mov ax, [es:bx+si]
    pop es
    mov bx, 100
    mul bx
    add ax, 128
    adc dx, 0
    mov bx, 256
    div bx
    ret

wait_tick:
    push es
    mov ax, 40h
    mov es, ax
    mov ax, [es:6Ch]
.wait:
    sti
    hlt
    cmp ax, [es:6Ch]
    je .wait
    pop es
    ret

read_driver:
    mov ax, 3
    int 33h
    mov [pos_x], cx
    mov [pos_y], dx
    mov [buttons], bl
    mov ax, 26h
    int 33h
    mov [max_x], cx
    mov [max_y], dx
    ret

; Build and write every line of the panel.
draw_info:
    mov ax, 2
    int 33h
    mov byte [line_no], 0

    mov di, line
    mov si, txt_title
    call put_text
    cmp word [umd_seg], 0
    jne .umd
    mov si, txt_other
    call put_text
    jmp .title_done
.umd:
    mov si, txt_x
    call put_text
    mov si, 0
    call percent
    call put_number
    mov si, txt_pct_y
    call put_text
    mov si, 2
    call percent
    call put_number
    mov al, '%'
    stosb
.title_done:
    call put_line

    mov di, line
    mov si, txt_pos
    call put_text
    mov ax, [pos_x]
    call put_number
    mov si, txt_y
    call put_text
    mov ax, [pos_y]
    call put_number
    mov si, txt_buttons
    call put_text
    mov al, [buttons]
    mov cx, 3
    mov si, txt_lmr
.button:
    shr al, 1
    jnc .up
    movsb
    jmp .next
.up:
    inc si
    mov byte [di], '-'
    inc di
.next:
    mov byte [di], ' '
    inc di
    loop .button
    call put_line

    mov di, line
    mov si, txt_last
    call put_text
    mov ax, [last_dx]
    call put_signed
    mov si, txt_dy
    call put_text
    mov ax, [last_dy]
    call put_signed
    mov si, txt_events
    call put_text
    mov ax, [events]
    call put_number
    mov si, txt_mask
    call put_text
    mov al, [last_mask]
    call put_hex
    call put_line

    mov di, line
    mov si, txt_total
    call put_text
    mov ax, [total_x]
    call put_signed
    mov si, txt_y
    call put_text
    mov ax, [total_y]
    call put_signed
    call put_line

    mov di, line
    mov si, txt_range
    call put_text
    mov ax, [max_x]
    call put_number
    mov si, txt_by
    call put_text
    mov ax, [max_y]
    call put_number
    call put_line

    mov di, line
    mov si, txt_keys
    call put_text
    call put_line

    mov di, line
    cmp word [umd_seg], 0
    je .no_options
    mov si, txt_options
    call put_text
    mov si, 0
    call percent
    call put_number
    mov si, txt_opt_y
    call put_text
    mov si, 2
    call percent
    call put_number
.no_options:
    mov si, txt_keys2
    call put_text
    call put_line

    mov ax, 1
    int 33h
    ret

; Write the line buffer at DI, padded to 40 columns, in white on black.
put_line:
    mov al, ' '
.pad:
    cmp di, line+40
    jae .write
    stosb
    jmp .pad
.write:
    push es
    mov si, line
    mov cx, 40
    cmp byte [graphics], 0
    jne .font
    mov ax, 0B800h
    mov es, ax
    mov al, [line_no]
    mov ah, 160
    mul ah
    mov di, ax
    mov ah, 0Fh
.cell:
    lodsb
    stosw
    loop .cell
    jmp .done
.font:
    mov ax, 0A000h
    mov es, ax
    mov al, [line_no]
    mov ah, 8*320/256
    mul ah
    shl ax, 8                   ; row * 8 * 320
    mov di, ax
.char:
    lodsb
    push cx
    push si
    mov ah, 0
    shl ax, 3
    mov si, ax
    add si, [font]
    push ds
    mov ds, [font+2]
    mov cx, 8
.glyph:
    lodsb
    mov ah, al
    push cx
    mov cx, 8
.pixel:
    shl ah, 1
    mov al, 0
    jnc .dark
    mov al, 15
.dark:
    stosb
    loop .pixel
    pop cx
    add di, 320-8
    loop .glyph
    pop ds
    sub di, 8*320-8
    pop si
    pop cx
    loop .char
.done:
    pop es
    inc byte [line_no]
    ret

put_text:
    lodsb
    test al, al
    jz .done
    stosb
    jmp put_text
.done:
    ret

put_signed:
    test ax, ax
    jns .plus
    neg ax
    mov byte [di], '-'
    inc di
    jmp put_number
.plus:
    mov byte [di], '+'
    inc di
put_number:
    xor cx, cx
    mov bx, 10
.digit:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .digit
.out:
    pop ax
    add al, '0'
    stosb
    loop .out
    ret

put_hex:
    mov ah, al
    shr al, 4
    call .digit
    mov al, ah
    and al, 15
.digit:
    add al, '0'
    cmp al, '9'
    jbe .store
    add al, 7
.store:
    stosb
    ret

print_number:
    mov di, line
    call put_number
    mov byte [di], '$'
    mov dx, line
    mov ah, 9
    int 21h
    ret

; Driver event handler: AX events, BX buttons, SI DI mickeys.
handler:
    inc word [cs:events]
    mov [cs:last_mask], al
    test al, 1
    jz .done
    mov [cs:last_dx], si
    mov [cs:last_dy], di
    add [cs:total_x], si
    add [cs:total_y], di
.done:
    retf

umd_seg   dw 0
font      dd 0
umd_off   dw 0
graphics  db 0
line_no   db 0
pos_x     dw 0
pos_y     dw 0
max_x     dw 0
max_y     dw 0
buttons   db 0
events    dw 0
last_mask db 0
last_dx   dw 0
last_dy   dw 0
total_x   dw 0
total_y   dw 0
line      times 48 db 0

txt_title   db 'MOUSTEST ', UMD_VERSION, ' ', 0
txt_other   db 'driver is not uMD', 0
txt_x       db 'uMD X=', 0
txt_pct_y   db '% Y=', 0
txt_pos     db 'Pos X=', 0
txt_y       db ' Y=', 0
txt_buttons db '  Btn ', 0
txt_lmr     db 'LRM'
txt_last    db 'Last dX=', 0
txt_dy      db ' dY=', 0
txt_events  db ' Ev=', 0
txt_mask    db ' M=', 0
txt_total   db 'Total X=', 0
txt_range   db 'Range 0..', 0
txt_by      db ' x 0..', 0
txt_keys    db 'Left/Right:X Up/Down:Y M:mode', 0
txt_options db 'UMD /X', 0
txt_opt_y   db ' /Y', 0
txt_keys2   db '  R:reset Esc:quit', 0
msg_no_driver db 'No mouse driver is installed.', 13, 10, '$'
msg_result  db 'Sensitivity: UMD /X$'
msg_y       db ' /Y$'
msg_crlf    db 13, 10, '$'
