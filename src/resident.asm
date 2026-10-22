; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Resident part: INT 33h service, INT 10h hook, and the BIOS PS/2 device
; handler.

; Caller registers after "push ds / push es / pusha" with BP = SP.
F_DI equ 0
F_SI equ 2
F_BX equ 8
F_DX equ 10
F_CX equ 12
F_AX equ 14
F_ES equ 16
F_DS equ 18

; One 16-byte block per axis.
A_POS   equ 0           ; virtual position
A_MIN   equ 2
A_MAX   equ 4
A_MICK  equ 6           ; mickey counter for function 0Bh
A_RATIO equ 8           ; mickeys per 8 virtual pixels
A_MULT  equ 10          ; count to mickey multiplier, 8.8 fixed point
A_PFRAC equ 12          ; pixel remainder
A_MFRAC equ 14          ; mickey fraction

LAST_FUNCTION equ 27h   ; 31h is dispatched as 27h

; Runtime scratch lives in the reserved PSP bytes 3Ch to 5Bh. DOS does not
; read them. The saved mouse state follows in the command tail area; functions
; 15h to 17h copy it as one block.
absolute 3Ch
drawn         resb 1
op            resb 1
plane         resb 1
seq_index     resb 1
map_mask      resb 1
gc_index      resb 1
gc_saved      resb 5
drawn_x       resw 1
drawn_y       resw 1
saved_word    resw 1
row           resw 1
row_addr      resw 1
first         resw 1
count         resw 1
save_ptr      resw 1
%if $ > 5Ch
%error "The scratch area runs into the saved state."
%endif
absolute 5Ch
state:
axis_x        resb 16
axis_y        resb 16
buttons       resb 1
level         resb 1    ; 0 shown, negative hidden
press_count   resw 3
press_x       resw 3
press_y       resw 3
release_count resw 3
release_x     resw 3
release_y     resw 3
sens_x        resb 1
sens_y        resb 1
threshold     resb 1
excl_on       resb 1
user_mask     resw 1
user_handler  resd 1
hot_x         resw 1
hot_y         resw 1
text_and      resw 1
text_xor      resw 1
excl_x1       resw 1
excl_y1       resw 1
excl_x2       resw 1
excl_y2       resw 1
page          resb 1
events        resb 1
masks         resb 64   ; 16 screen mask rows, then 16 cursor mask rows
state_end:
%if state_end > 100h
%error "The saved state does not fit in the PSP."
%endif
section .text

scale_x equ int33.scale_x
scale_y equ int33.scale_y
pos_x   equ axis_x+A_POS
min_x   equ axis_x+A_MIN
max_x   equ axis_x+A_MAX
mick_x  equ axis_x+A_MICK
ratio_x equ axis_x+A_RATIO
mult_x  equ axis_x+A_MULT
pos_y   equ axis_y+A_POS
min_y   equ axis_y+A_MIN
max_y   equ axis_y+A_MAX
mick_y  equ axis_y+A_MICK
ratio_y equ axis_y+A_RATIO
mult_y  equ axis_y+A_MULT

; ---------------------------------------------------------------------------
; INT 33h

; The signature and the two sensitivity scales (8.8 fixed point) sit behind
; the entry jump, so that UMD and MOUSTEST find them at the vector plus 2.
int33:
    jmp short .entry
.signature db 'uMD', 0
.scale_x dw 100h
.scale_y dw 100h
.entry:
    cmp ax, 31h
    jne .range
    mov al, LAST_FUNCTION
.range:
    cmp ax, LAST_FUNCTION
    ja .unknown
    push ds
    push es
    pusha
    mov bp, sp
    push cs
    pop ds
    mov bx, ax
    shl bx, 1
    call [functions+bx]
    popa
    pop es
    pop ds
.unknown:
    iret

functions:
    dw f_reset, f_show, f_hide, f_status                    ; 00h to 03h
    dw f_set_position, f_press, f_release                   ; 04h to 06h
    dw f_x_range, f_y_range, f_graphics_cursor              ; 07h to 09h
    dw f_text_cursor, f_motion, f_handler                   ; 0Ah to 0Ch
    dw f_none, f_none, f_ratio, f_exclude                   ; 0Dh to 10h
    dw f_none, f_none, f_threshold, f_exchange              ; 11h to 14h
    dw f_state_size, f_save, f_restore                      ; 15h to 17h
    dw f_alternate, f_alternate_get                         ; 18h, 19h
    dw f_sensitivity, f_get_sensitivity, f_none             ; 1Ah to 1Ch
    dw f_page, f_get_page, f_disable, f_enable              ; 1Dh to 20h
    dw f_reset, f_none, f_language, f_version               ; 21h to 24h
    dw f_none, f_max_coordinates                            ; 25h, 26h
    dw f_range                                              ; 31h

f_none:
    ret

; 00h reset, 21h software reset.
f_reset:
    call reset_state
    mov word [bp+F_AX], 0FFFFh
    mov word [bp+F_BX], 3
    ret

; 01h
f_show:
    call video_check
    cmp byte [level], 0
    jge .done
    inc byte [level]
    mov byte [excl_on], 0
    jmp refresh
.done:
    ret

; 02h
f_hide:
    dec byte [level]
    jmp refresh

; 03h
f_status:
    mov al, [buttons]
    mov ah, 0
    mov [bp+F_BX], ax
    mov ax, [pos_x]
    mov [bp+F_CX], ax
    mov ax, [pos_y]
    mov [bp+F_DX], ax
    ret

; 04h
f_set_position:
    mov ax, [bp+F_CX]
    mov [pos_x], ax
    mov ax, [bp+F_DX]
    mov [pos_y], ax
    call clamp
    jmp refresh

; 05h press, 06h release. BX selects the button.
f_press:
    mov si, press_count
    jmp button_info
f_release:
    mov si, release_count
button_info:
    mov al, [buttons]
    mov ah, 0
    mov [bp+F_AX], ax
    mov bx, [bp+F_BX]
    cmp bx, 2
    jbe .index
    xor bx, bx
.index:
    shl bx, 1
    mov ax, [si+bx]
    mov [bp+F_BX], ax
    mov word [si+bx], 0
    mov ax, [si+bx+6]
    mov [bp+F_CX], ax
    mov ax, [si+bx+12]
    mov [bp+F_DX], ax
    ret

; 07h, 08h: CX minimum, DX maximum.
f_x_range:
    mov si, axis_x
    jmp set_range
f_y_range:
    mov si, axis_y
set_range:
    mov ax, [bp+F_CX]
    mov dx, [bp+F_DX]
    cmp ax, dx
    jle .ordered
    xchg ax, dx
.ordered:
    mov [si+A_MIN], ax
    mov [si+A_MAX], dx
    call clamp
    jmp refresh

; 09h: BX, CX hot spot, ES:DX masks.
f_graphics_cursor:
    mov ax, [bp+F_BX]
    mov [hot_x], ax
    mov ax, [bp+F_CX]
    mov [hot_y], ax
    push ds
    pop es
    mov di, masks
    mov si, [bp+F_DX]
    mov ds, [bp+F_ES]
    mov cx, 32
    rep movsw
    push cs
    pop ds
    jmp redraw

; 0Ah: BX=0 software cursor, CX screen mask, DX cursor mask.
f_text_cursor:
    cmp word [bp+F_BX], 0
    jne .done
    mov ax, [bp+F_CX]
    mov [text_and], ax
    mov ax, [bp+F_DX]
    mov [text_xor], ax
    jmp redraw
.done:
    ret

; 0Bh
f_motion:
    xor ax, ax
    xchg ax, [mick_x]
    mov [bp+F_CX], ax
    xor ax, ax
    xchg ax, [mick_y]
    mov [bp+F_DX], ax
    ret

; 0Ch: CX event mask, ES:DX handler.
f_handler:
    mov ax, [bp+F_CX]
    mov [user_mask], ax
    mov ax, [bp+F_DX]
    mov [user_handler], ax
    mov ax, [bp+F_ES]
    mov [user_handler+2], ax
    ret

; 0Fh: CX, DX mickeys per 8 pixels.
f_ratio:
    mov ax, [bp+F_CX]
    test ax, ax
    jz .y
    mov [ratio_x], ax
.y:
    mov ax, [bp+F_DX]
    test ax, ax
    jz .done
    mov [ratio_y], ax
.done:
    ret

; 10h: CX, DX upper left and SI, DI lower right of the exclusion area.
f_exclude:
    mov ax, [bp+F_CX]
    mov [excl_x1], ax
    mov ax, [bp+F_DX]
    mov [excl_y1], ax
    mov ax, [bp+F_SI]
    mov [excl_x2], ax
    mov ax, [bp+F_DI]
    mov [excl_y2], ax
    mov byte [excl_on], 1
    jmp refresh

; 13h: the threshold is stored but not used. uMD has no acceleration.
f_threshold:
    mov al, [bp+F_DX]
    mov [threshold], al
    ret

; 14h
f_exchange:
    mov ax, [user_mask]
    xchg ax, [bp+F_CX]
    mov [user_mask], ax
    mov ax, [user_handler]
    xchg ax, [bp+F_DX]
    mov [user_handler], ax
    mov ax, [user_handler+2]
    xchg ax, [bp+F_ES]
    mov [user_handler+2], ax
    ret

; 15h
f_state_size:
    mov word [bp+F_BX], state_end-state
    ret

; 16h: copy the state to ES:DX.
f_save:
    mov si, state
    mov di, [bp+F_DX]
    mov es, [bp+F_ES]
    mov cx, (state_end-state)/2
    rep movsw
    ret

; 17h: copy the state from ES:DX.
f_restore:
    call erase
    push ds
    pop es
    mov di, state
    mov si, [bp+F_DX]
    mov ds, [bp+F_ES]
    mov cx, (state_end-state)/2
    rep movsw
    push cs
    pop ds
    jmp refresh

; 18h, 19h: alternate handlers are not supported.
f_alternate:
    mov word [bp+F_AX], 0FFFFh
    ret
f_alternate_get:
    mov word [bp+F_CX], 0
    ret

; 1Ah: BX, CX sensitivity (1 to 100, 50 is normal), DX threshold.
f_sensitivity:
    mov al, [bp+F_BX]
    mov [sens_x], al
    mov al, [bp+F_CX]
    mov [sens_y], al
    mov al, [bp+F_DX]
    mov [threshold], al
    jmp compute_mult

; 1Bh
f_get_sensitivity:
    mov al, [sens_x]
    mov ah, 0
    mov [bp+F_BX], ax
    mov al, [sens_y]
    mov [bp+F_CX], ax
    mov al, [threshold]
    mov [bp+F_DX], ax
    ret

; 1Dh, 1Eh
f_page:
    mov al, [bp+F_BX]
    mov [page], al
    ret
f_get_page:
    mov al, [page]
    mov ah, 0
    mov [bp+F_BX], ax
    ret

; 1Fh: report the vector that uMD replaced. The driver stays active.
f_disable:
    mov word [bp+F_AX], 1Fh
    mov ax, [old33]
    mov [bp+F_BX], ax
    mov ax, [old33+2]
    mov [bp+F_ES], ax
    ret

; 20h: take INT 33h again.
f_enable:
    xor ax, ax
    mov es, ax
    mov word [es:33h*4], int33
    mov [es:33h*4+2], cs
    ret

; 23h
f_language:
    mov word [bp+F_BX], 0
    ret

; 24h: version 6.26, PS/2 mouse.
f_version:
    mov word [bp+F_BX], 0626h
    mov word [bp+F_CX], 0400h
    ret

; 26h
f_max_coordinates:
    mov word [bp+F_BX], 0
    mov ax, [scr_w]
    dec ax
    mov [bp+F_CX], ax
    mov ax, [scr_h]
    dec ax
    mov [bp+F_DX], ax
    ret

; 31h
f_range:
    mov ax, [min_x]
    mov [bp+F_AX], ax
    mov ax, [min_y]
    mov [bp+F_BX], ax
    mov ax, [max_x]
    mov [bp+F_CX], ax
    mov ax, [max_y]
    mov [bp+F_DX], ax
    ret

; ---------------------------------------------------------------------------
; State

clamp:
    mov si, axis_x
    call clamp_axis
    mov si, axis_y
clamp_axis:
    mov ax, [si+A_POS]
    cmp ax, [si+A_MIN]
    jge .low
    mov ax, [si+A_MIN]
.low:
    cmp ax, [si+A_MAX]
    jle .high
    mov ax, [si+A_MAX]
.high:
    mov [si+A_POS], ax
    ret

; mult = scale * sensitivity / 50 for both axes.
compute_mult:
    mov si, axis_x
    mov ax, [scale_x]
    mov bl, [sens_x]
    call .axis
    mov si, axis_y
    mov ax, [scale_y]
    mov bl, [sens_y]
.axis:
    mov bh, 0
    test bl, bl
    jnz .valid
    inc bx
.valid:
    mul bx
    mov bx, 50
    div bx
    mov [si+A_MULT], ax
    ret

; Functions 00h and 21h.
reset_state:
    call erase
    push ds
    pop es
    mov di, state
    mov cx, (masks-state)/2
    xor ax, ax
    rep stosw
    mov si, default_masks
    mov cx, 32
    rep movsw
    mov byte [level], -1
    mov word [ratio_x], 8
    mov word [ratio_y], 16
    mov word [sens_x], 3232h
    mov byte [threshold], 64
    mov word [text_and], 77FFh
    mov word [text_xor], 7700h
    call compute_mult
; Read the video mode, then center the pointer in the full screen.
video_reset:
    call video_init
    xor ax, ax
    mov [min_x], ax
    mov [min_y], ax
    mov ax, [scr_w]
    dec ax
    mov [max_x], ax
    inc ax
    shr ax, 1
    mov [pos_x], ax
    mov ax, [scr_h]
    dec ax
    mov [max_y], ax
    inc ax
    shr ax, 1
    mov [pos_y], ax
    ret

; Start again when the BIOS mode or the screen size changed without INT 10h
; function 00h.
video_check:
    push es
    mov ax, 40h
    mov es, ax
    mov al, [es:49h]
    mov ah, [es:84h]
    cmp ax, [mode_key]
    jne .changed
    mov al, [es:4Ah]
    cmp al, [mode_key+2]
    je .same
.changed:
    pop es
    mov byte [drawn], 0
    jmp video_reset
.same:
    pop es
    ret

; Mode 0 to 13h: 0 text at B800h, 1 text at B000h, 2 CGA 2 bpp, 3 CGA 1 bpp,
; 4 planar, 5 one byte per pixel.
mode_types:
    db 0, 0, 0, 0, 2, 2, 3, 1, 0FFh, 0FFh, 0FFh, 0FFh, 0FFh, 4, 4, 4, 4, 4, 4, 5
; Per type, in the order of the video variables: bpp shift, planes, bits per
; pixel, pixel mask, interleave high byte, segment high byte.
type_params:
    db 1, 1, 2, 3, 0, 0B8h
    db 1, 1, 2, 3, 0, 0B0h
    db 1, 1, 2, 3, 20h, 0B8h
    db 0, 1, 1, 1, 20h, 0B8h
    db 0, 4, 1, 1, 0, 0A0h
    db 3, 1, 8, 0FFh, 0, 0A0h

video_init:
    push es
    mov ax, 40h
    mov es, ax
    mov al, [es:49h]
    mov ah, [es:84h]
    mov [mode_key], ax
    mov al, ah
    inc al
    mov ah, 0
    mul word [es:85h]
    mov [height], ax
    mov dl, [es:4Ah]
    mov [mode_key+2], dl
    mov bl, [es:49h]
    pop es
    mov bh, 0
    mov al, 0FFh
    cmp bl, 13h
    ja .type
    mov al, [mode_types+bx]
.type:
    mov [vtype], al
    cmp al, 0FFh
    je .size
    mov bl, 6
    mul bl
    mov si, ax
    add si, type_params
    push ds
    pop es
    mov di, bpp_shift
    movsw
    movsw
    lodsb
    mov [interleave+1], al
    lodsb
    mov [vseg+1], al
    mov al, dl
    mov ah, 0
    mov cl, [bpp_shift]
    shl ax, cl
    mov [stride], ax
.size:
    mov al, dl
    mov ah, 0
    shl ax, 3
    mov [width], ax
    mov cl, 0
    cmp ax, 320
    jne .shift
    inc cl
.shift:
    mov [xshift], cl
    shl ax, cl
    mov [scr_w], ax
    mov ax, [height]
    cmp byte [vtype], 1
    ja .graphics
    mov al, [mode_key+1]
    inc al
    mov ah, 0
    shl ax, 3
.graphics:
    mov [scr_h], ax
    ret

; ---------------------------------------------------------------------------
; INT 10h: a mode set hides the pointer and starts the ranges again.

int10:
    cmp ah, 0
    jne .chain
    pushf
    call far [cs:old10]
    push ds
    push es
    pusha
    push cs
    pop ds
    mov byte [drawn], 0
    mov byte [level], -1
    call video_reset
    popa
    pop es
    pop ds
    iret
.chain:
    jmp far [cs:old10]

; ---------------------------------------------------------------------------
; BIOS PS/2 device handler. The BIOS pushes status, X, Y, and Z words and
; makes a far call. The handler runs on the stack of the interrupted program.

ps2_handler:
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

; AL status, BL X count, CL Y count.
process_packet:
    mov dl, al
    mov byte [events], 0
    mov dh, bl
    or dh, cl
    jz .still
    mov byte [events], 1
.still:
    mov dh, cl
    mov al, bl
    mov ah, 0
    test dl, 10h
    jz .x
    mov ah, 0FFh
.x:
    push dx
    mov si, axis_x
    call move_axis
    mov [last_mick_x], ax
    pop dx
    mov al, dh
    mov ah, 0
    test dl, 20h
    jz .y
    mov ah, 0FFh
.y:
    neg ax                  ; PS/2 counts up as positive
    push dx
    mov si, axis_y
    call move_axis
    mov [last_mick_y], ax
    pop dx
    mov al, dl
    and al, 7
    mov ah, [buttons]
    mov [buttons], al
    xor ah, al              ; changed buttons
    mov dl, 1               ; button bit
    mov dh, 2               ; press event bit
    xor bx, bx
.button:
    test ah, dl
    jz .next
    mov si, release_count
    mov ch, dh
    shl ch, 1
    test al, dl
    jz .changed
    mov si, press_count
    mov ch, dh
.changed:
    or [events], ch
    inc word [si+bx]
    mov di, [pos_x]
    mov [si+bx+6], di
    mov di, [pos_y]
    mov [si+bx+12], di
.next:
    shl dl, 1
    shl dh, 2
    add bx, 2
    cmp bx, 6
    jb .button
    call refresh
    mov al, [events]
    test al, [user_mask]
    jz .done
    mov ah, 0
    mov bl, [buttons]
    mov bh, 0
    mov cx, [pos_x]
    mov dx, [pos_y]
    mov si, [last_mick_x]
    mov di, [last_mick_y]
    call far [user_handler]
    push cs
    pop ds
.done:
    ret

; SI axis, AX signed count. Returns AX = mickeys.
move_axis:
    imul word [si+A_MULT]
    add al, [si+A_MFRAC]
    adc ah, 0
    adc dx, 0
    mov [si+A_MFRAC], al
    mov al, ah
    mov ah, dl
    add [si+A_MICK], ax
    push ax
    shl ax, 3
    cwd
    mov bx, [si+A_PFRAC]
    mov cx, bx
    sar cx, 15
    add ax, bx
    adc dx, cx
    idiv word [si+A_RATIO]
    mov [si+A_PFRAC], dx
    add [si+A_POS], ax
    call clamp_axis
    pop ax
    ret
