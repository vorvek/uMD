; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Guest test for uMD. Prints PASS, or FAIL, the test number, and AX BX CX DX,
; and exits with code 1 on failure.
;
;   MTEST     API and pointer tests. The motion tests are skipped.
;   MTEST /W  Also wait for mouse packets that the emulator injects, in the
;             order that scripts/izarra_test.py sends them, and exit through
;             the IzarraVM test port.
;   MTEST /N  Expect no mouse driver.

cpu 286
bits 16
org 100h

WAIT_TICKS equ 18*20            ; 20 seconds for each injected packet

%macro expect 2
    cmp %1, %2
    jne fail
%endmacro

%macro tcase 1
    mov byte [test_no], %1
%endmacro

start:
    cld
    mov si, 81h
.scan:
    lodsb
    cmp al, 13
    je .run
    and al, 0DFh
    cmp al, 'W'
    jne .not_w
    mov byte [wait_mode], 1
.not_w:
    cmp al, 'N'
    jne .scan
    tcase 90
    mov ax, 3533h
    int 21h
    mov ax, es
    or ax, bx
    jz pass
    xor ax, ax
    int 33h
    cmp ax, 0FFFFh
    je fail
    jmp pass

.run:
    tcase 1                     ; the vector is set and is not an IRET
    mov ax, 3533h
    int 21h
    mov ax, es
    or ax, bx
    jz fail
    cmp byte [es:bx], 0CFh
    je fail

    tcase 2                     ; reset
    xor ax, ax
    int 33h
    expect ax, 0FFFFh
    expect bx, 3

    tcase 3                     ; version and type: 2 serial or 4 PS/2
    mov ax, 24h
    int 33h
    expect bh, 6
    cmp ch, 2
    je type_ok
    expect ch, 4
type_ok:

    tcase 4                     ; center of the 640x200 text screen
    mov ax, 3
    int 33h
    expect bx, 0
    expect cx, 320
    expect dx, 100

    tcase 5                     ; set position
    mov ax, 4
    mov cx, 10
    mov dx, 20
    int 33h
    mov ax, 3
    int 33h
    expect cx, 10
    expect dx, 20

    tcase 6                     ; clamp to the screen
    mov ax, 4
    mov cx, 700
    mov dx, 300
    int 33h
    mov ax, 3
    int 33h
    expect cx, 639
    expect dx, 199

    tcase 7                     ; ranges
    mov ax, 7
    mov cx, 100
    mov dx, 200
    int 33h
    mov ax, 8
    mov cx, 50
    mov dx, 150
    int 33h
    mov ax, 4
    xor cx, cx
    xor dx, dx
    int 33h
    mov ax, 3
    int 33h
    expect cx, 100
    expect dx, 50
    mov ax, 31h
    int 33h
    expect ax, 100
    expect bx, 50
    expect cx, 200
    expect dx, 150
    mov ax, 26h
    int 33h
    expect bx, 0
    expect cx, 639
    expect dx, 199
    xor ax, ax
    int 33h
    mov ax, 3
    int 33h
    expect cx, 320
    expect dx, 100

    cmp byte [wait_mode], 0
    je text_tests

    tcase 8                     ; 16 mickeys right
    call wait_move
    expect cx, 336
    expect dx, 100
    mov ax, 0Bh
    int 33h
    expect cx, 16
    expect dx, 0
    mov ax, 0Bh
    int 33h
    expect cx, 0
    expect dx, 0

    tcase 9                     ; 8 mickeys down, vertical ratio 16
    call wait_move
    expect cx, 336
    expect dx, 104

    tcase 10                    ; left button press and release
    call wait_buttons
    expect bx, 1
    mov ax, 5
    xor bx, bx
    int 33h
    expect ax, 1
    expect bx, 1
    expect cx, 336
    expect dx, 104
    call wait_buttons
    expect bx, 0
    mov ax, 6
    xor bx, bx
    int 33h
    expect ax, 0
    expect bx, 1
    mov ax, 6
    xor bx, bx
    int 33h
    expect bx, 0

    tcase 11                    ; event handler: press, move 4, release
    mov ax, 0Ch
    mov cx, 0FFh
    push cs
    pop es
    mov dx, handler
    int 33h
    mov byte [h_count], 0
    call wait_buttons           ; press
    call wait_move              ; move with the button held
    call wait_buttons           ; release
    mov al, [h_count]
    mov ah, [h_events]
    mov bl, [h_events+1]
    mov bh, [h_events+2]
    mov cx, [h_si]
    mov dx, [h_bx]
    expect al, 3
    expect ah, 2
    expect bl, 1
    expect bh, 4
    expect cx, 4
    expect dx, 1
    mov cx, [h_cx]
    mov dx, [h_dx]
    expect cx, 340
    expect dx, 104
    expect word [h_di], 0
    mov ax, 0Ch
    xor cx, cx
    int 33h

text_tests:
    tcase 12                    ; text pointer
    mov ax, 4
    xor cx, cx
    xor dx, dx
    int 33h
    mov ax, 0B800h
    mov es, ax
    mov word [es:0], 0741h
    mov word [es:4], 0742h
    mov ax, 1
    int 33h
    expect word [es:0], 7041h
    mov ax, 2
    int 33h
    expect word [es:0], 0741h
    mov ax, 0Ah
    xor bx, bx
    xor cx, cx
    mov dx, 0F18h
    int 33h
    mov ax, 1
    int 33h
    expect word [es:0], 0F18h
    mov ax, 4
    mov cx, 16
    xor dx, dx
    int 33h
    expect word [es:0], 0741h
    expect word [es:4], 0F18h
    mov ax, 2
    int 33h
    expect word [es:4], 0742h

    tcase 13                    ; sensitivity 100 doubles the movement
    mov ax, 1Ah
    mov bx, 100
    mov cx, 100
    mov dx, 64
    int 33h
    mov ax, 1Bh
    int 33h
    expect bx, 100
    expect cx, 100
    expect dx, 64
    mov ax, 4
    mov cx, 320
    mov dx, 100
    int 33h
    cmp byte [wait_mode], 0
    je .sensitivity_done
    call wait_move
    expect cx, 352
.sensitivity_done:
    mov ax, 1Ah
    mov bx, 50
    mov cx, 50
    mov dx, 64
    int 33h

    tcase 14                    ; save and restore
    mov ax, 4
    mov cx, 320
    mov dx, 100
    int 33h
    mov ax, 15h
    int 33h
    test bx, bx
    jz fail
    cmp bx, 512
    ja fail
    mov ax, 16h
    push cs
    pop es
    mov dx, statebuf
    int 33h
    mov ax, 4
    xor cx, cx
    xor dx, dx
    int 33h
    mov ax, 17h
    mov dx, statebuf
    int 33h
    mov ax, 3
    int 33h
    expect cx, 320
    expect dx, 100

    tcase 15                    ; mode 13h pointer
    mov ax, 13h
    int 10h
    xor ax, ax
    int 33h
    mov ax, 3
    int 33h
    expect cx, 320
    expect dx, 100
    mov ax, 0A000h
    mov es, ax
    xor di, di
    mov cx, 8000h
    mov ax, 5555h
    rep stosw
    mov ax, 4
    mov cx, 200
    mov dx, 100
    int 33h
    mov ax, 1
    int 33h
    expect byte [es:100*320+100], 0
    expect byte [es:101*320+101], 0Fh
    expect byte [es:100*320+103], 55h
    mov si, 100*320+100
    call check_arrow
    mov ax, 2
    int 33h
    mov si, 100*320+100
    call check_block

    tcase 16                    ; clipping at the corners
    mov ax, 4
    xor cx, cx
    xor dx, dx
    int 33h
    mov ax, 1
    int 33h
    expect byte [es:0], 0
    expect byte [es:321], 0Fh
    mov ax, 2
    int 33h
    expect byte [es:0], 55h
    expect byte [es:321], 55h
    mov ax, 4
    mov cx, 638
    mov dx, 199
    int 33h
    mov ax, 1
    int 33h
    expect byte [es:199*320+319], 0
    expect byte [es:199*320+318], 55h
    expect byte [es:0FA00h], 55h
    mov ax, 2
    int 33h
    expect byte [es:199*320+319], 55h

    tcase 17                    ; mode 12h planar pointer
    mov ax, 12h
    int 10h
    xor ax, ax
    int 33h
    xor di, di
    mov cx, 19200
    mov ax, 0F0F0h
    rep stosw
    mov dx, 3CEh
    mov ax, 0F008h              ; bit mask F0h
    out dx, ax
    mov dx, 3C4h
    mov ax, 0502h               ; map mask 5
    out dx, ax
    mov ax, 4
    mov cx, 100
    mov dx, 100
    int 33h
    mov ax, 1
    int 33h
    call check_vga_regs
    mov cx, 4
.white:                         ; pixel (101,101) is set in every plane
    mov si, 101*80+12
    call read_plane
    test al, 04h
    jz fail
    mov si, 100*80+12           ; pixel (100,100) is clear in every plane
    call read_plane
    test al, 08h
    jnz fail
    loop .white
    mov ax, 2
    int 33h
    call check_vga_regs
    mov cx, 4
.restored:
    mov si, 101*80+12
    call read_plane
    expect al, 0F0h
    mov si, 100*80+12
    call read_plane
    expect al, 0F0h
    loop .restored
    mov dx, 3CEh
    mov ax, 0FF08h
    out dx, ax
    mov dx, 3C4h
    mov ax, 0F02h
    out dx, ax

    tcase 18                    ; back in text mode
    mov ax, 3
    int 10h
    mov ax, 21h
    int 33h
    expect ax, 0FFFFh
    mov ax, 1Fh
    int 33h
    expect ax, 1Fh
    mov ax, 20h
    int 33h
    xor ax, ax
    int 33h
    expect ax, 0FFFFh
    mov ax, 50h
    int 33h
    expect ax, 50h

pass:
    mov dx, msg_pass
    mov ah, 9
    int 21h
    mov al, 0
    call test_exit
    mov ax, 4C00h
    int 21h

fail:
    mov [f_ax], ax
    mov [f_bx], bx
    mov [f_cx], cx
    mov [f_dx], dx
    mov ax, 3
    int 10h
    mov dx, msg_fail
    mov ah, 9
    int 21h
    mov al, [test_no]
    mov ah, 0
    mov bl, 10
    div bl
    push ax
    add al, '0'
    mov dl, al
    mov ah, 2
    int 21h
    pop ax
    mov dl, ah
    add dl, '0'
    mov ah, 2
    int 21h
    mov si, f_ax
    mov cx, 4
.register:
    mov dl, ' '
    mov ah, 2
    int 21h
    lodsw
    call hex
    loop .register
    mov dx, msg_crlf
    mov ah, 9
    int 21h
    mov al, [test_no]
    call test_exit
    mov ax, 4C01h
    int 21h

; In wait mode, stop the emulator through the IzarraVM test port with AL.
test_exit:
    cmp byte [wait_mode], 0
    je .done
    mov ah, al
    mov dx, 0E4h
    mov al, 12
    out dx, al
    inc dx
    mov al, ah
    out dx, al
    inc dx
    mov al, 3
    out dx, al
.done:
    ret

; Print AX in hex.
hex:
    push cx
    mov cx, 4
.digit:
    rol ax, 4
    push ax
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .print
    add al, 7
.print:
    mov dl, al
    mov ah, 2
    int 21h
    pop ax
    loop .digit
    pop cx
    ret

; Wait until the position changes. Returns the new BX, CX, DX of function 03h.
wait_move:
    mov ax, 3
    int 33h
    mov [w_cx], cx
    mov [w_dx], dx
    call wait_start
.poll:
    call wait_tick
    mov ax, 3
    int 33h
    cmp cx, [w_cx]
    jne .done
    cmp dx, [w_dx]
    je .poll
.done:
    ret

; Wait until the button state changes. Returns BX, CX, DX of function 03h.
wait_buttons:
    mov ax, 3
    int 33h
    mov [w_bx], bx
    call wait_start
.poll:
    call wait_tick
    mov ax, 3
    int 33h
    cmp bx, [w_bx]
    je .poll
    ret

wait_start:
    push es
    push ax
    mov ax, 40h
    mov es, ax
    mov ax, [es:6Ch]
    add ax, WAIT_TICKS
    mov [w_end], ax
    pop ax
    pop es
    ret

; Sleep until the next timer tick. Fails when the wait runs out.
wait_tick:
    push es
    push ax
    mov ax, 40h
    mov es, ax
    mov ax, [es:6Ch]
.sleep:
    sti
    hlt
    cmp ax, [es:6Ch]
    je .sleep
    mov ax, [es:6Ch]
    cmp ax, [w_end]
    pop ax
    pop es
    je fail
    ret

; The 16x16 block at ES:SI must show the default arrow over 55h: a screen
; mask bit keeps the pixel, a cursor mask bit XORs it with 0Fh.
check_arrow:
    mov bx, arrow
    mov dx, 16
.row:
    push si
    mov cx, 16
.pixel:
    mov al, 55h
    test word [bx], 8000h
    jnz .keep
    mov al, 0
.keep:
    test word [bx+32], 8000h
    jz .plain
    xor al, 0Fh
.plain:
    expect [es:si], al
    inc si
    shl word [bx], 1
    shl word [bx+32], 1
    loop .pixel
    pop si
    add si, 320
    add bx, 2
    dec dx
    jnz .row
    ret

; 16 rows of 16 bytes at ES:SI must hold 55h.
check_block:
    mov dx, 16
.row:
    mov cx, 16
    mov di, si
.byte:
    expect byte [es:di], 55h
    inc di
    loop .byte
    add si, 320
    dec dx
    jnz .row
    ret

; The planar draw must leave the bit mask and the map mask as they were.
check_vga_regs:
    mov dx, 3CEh
    mov al, 8
    out dx, al
    inc dx
    in al, dx
    expect al, 0F0h
    mov dx, 3C4h
    mov al, 2
    out dx, al
    inc dx
    in al, dx
    expect al, 5
    ret

; CX-1 = plane. Returns AL = byte at ES:SI of that plane. Keeps CX.
read_plane:
    mov dx, 3CEh
    mov ax, cx
    dec ax
    mov ah, al
    mov al, 4
    out dx, ax
    mov al, [es:si]
    ret

; Record the event mask of each call, the position of the last call, and
; the buttons and mickeys of the motion call.
handler:
    push bx
    mov bl, [cs:h_count]
    mov bh, 0
    cmp bl, 3
    jae .full
    mov [cs:h_events+bx], al
    inc byte [cs:h_count]
.full:
    pop bx
    mov [cs:h_cx], cx
    mov [cs:h_dx], dx
    test al, 1
    jz .done
    mov [cs:h_bx], bx
    mov [cs:h_si], si
    mov [cs:h_di], di
.done:
    retf

test_no   db 0
wait_mode db 0
f_ax      dw 0
f_bx      dw 0
f_cx      dw 0
f_dx      dw 0
w_bx      dw 0
w_cx      dw 0
w_dx      dw 0
w_end     dw 0
h_count   db 0
h_events  db 0, 0, 0
h_bx      dw 0
h_cx      dw 0
h_dx      dw 0
h_si      dw 0
h_di      dw 0
msg_pass  db 'PASS', 13, 10, '$'
msg_fail  db 'FAIL $'
msg_crlf  db 13, 10, '$'
arrow:
    dw 3FFFh, 1FFFh, 0FFFh, 07FFh, 03FFh, 01FFh, 00FFh, 007Fh
    dw 003Fh, 001Fh, 01FFh, 10FFh, 30FFh, 0F87Fh, 0F87Fh, 0FC3Fh
    dw 0000h, 4000h, 6000h, 7000h, 7800h, 7C00h, 7E00h, 7F00h
    dw 7F80h, 7C00h, 6C00h, 4600h, 0600h, 0300h, 0300h, 0000h
statebuf  times 512 db 0
