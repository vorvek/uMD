; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only

; Pointer drawing in text, CGA, planar EGA/VGA, and 256-color modes.

; Erase the pointer if it is drawn, then draw it again if it is visible.
redraw:
    call erase
; Bring the drawn pointer in line with the position and the visibility.
refresh:
    cmp byte [level], 0
    jne erase
    cmp byte [vtype], 0FFh
    je erase
    cmp byte [excl_on], 0
    je .visible
    mov ax, [pos_x]
    cmp ax, [excl_x1]
    jl .visible
    cmp ax, [excl_x2]
    jg .visible
    mov ax, [pos_y]
    cmp ax, [excl_y1]
    jl .visible
    cmp ax, [excl_y2]
    jg .visible
    dec byte [level]
    mov byte [excl_on], 0
    jmp erase
.visible:
    call target
    cmp byte [drawn], 0
    je .draw
    cmp bx, [drawn_x]
    jne .move
    cmp cx, [drawn_y]
    jne .move
    ret
.move:
    push bx
    push cx
    call erase
    pop cx
    pop bx
.draw:
    mov [drawn_x], bx
    mov [drawn_y], cx
    mov byte [drawn], 1
    mov byte [op], 0
    jmp paint

; Put the screen content back.
erase:
    cmp byte [drawn], 0
    je .done
    mov byte [drawn], 0
    mov byte [op], 1
    jmp paint
.done:
    ret

; BX, CX = text cell, or top left pixel in graphics modes.
target:
    mov bx, [pos_x]
    mov cl, [xshift]
    sar bx, cl
    mov cx, [pos_y]
    cmp byte [vtype], 1
    ja .graphics
    sar bx, 3
    sar cx, 3
    ret
.graphics:
    sub bx, [hot_x]
    sub cx, [hot_y]
    ret

; Draw (op 0) or erase (op 1) at drawn_x, drawn_y.
paint:
    mov es, [vseg]
    cmp byte [vtype], 1
    ja paint_graphics
    cmp byte [op], 0
    jne .restore
    mov al, [mode_key+2]
    mov ah, 0
    mul word [drawn_y]
    add ax, [drawn_x]
    shl ax, 1
    push es
    mov bx, 40h
    mov es, bx
    add ax, [es:4Eh]
    pop es
    mov bx, ax
    mov [text_addr], bx
    mov ax, [es:bx]
    mov [saved_word], ax
    and ax, [text_and]
    xor ax, [text_xor]
    mov [es:bx], ax
    ret
.restore:
    mov bx, [text_addr]
    mov ax, [saved_word]
    mov [es:bx], ax
    ret

paint_graphics:
    cmp byte [vseg+1], 0A0h
    jne .start
    call vga_enter
.start:
    mov word [save_ptr], savebuf
    mov word [row], 0
.row:
    mov ax, [drawn_y]
    add ax, [row]
    js .next_row
    cmp ax, [height]
    jge .done
    mov bx, ax
    and bx, 1
    cmp word [interleave], 0
    je .linear
    shr ax, 1
.linear:
    mul word [stride]
    test bx, bx
    jz .address
    add ax, [interleave]
.address:
    mov [row_addr], ax
    mov ax, [drawn_x]
    mov bx, ax
    add bx, 15
    test ax, ax
    jns .left
    xor ax, ax
.left:
    mov cx, [width]
    dec cx
    cmp bx, cx
    jle .right
    mov bx, cx
.right:
    cmp ax, bx
    jg .next_row
    mov cl, [bpp_shift]
    shl ax, cl
    shr ax, 3
    mov [first], ax
    shl bx, cl
    shr bx, 3
    sub bx, ax
    inc bx
    mov [count], bx
    cmp byte [op], 0
    jne .planes
    call build_masks
.planes:
    mov byte [plane], 0
.plane:
    cmp byte [planes], 1
    je .copy
    mov ah, [plane]
    mov al, 4               ; read map select
    mov dx, 3CEh
    out dx, ax
    mov cl, ah
    mov ah, 1
    shl ah, cl
    mov al, 2               ; map mask
    mov dx, 3C4h
    out dx, ax
.copy:
    mov bx, [row_addr]
    add bx, [first]
    mov cx, [count]
    mov si, [save_ptr]
    cmp byte [op], 0
    jne .restore
    xor di, di
.byte:
    mov al, [es:bx]
    mov [si], al
    and al, [sbuf+di]
    xor al, [cbuf+di]
    mov [es:bx], al
    inc bx
    inc si
    inc di
    loop .byte
    jmp .stored
.restore:
    mov di, bx
    rep movsb
.stored:
    mov [save_ptr], si
    inc byte [plane]
    mov al, [plane]
    cmp al, [planes]
    jb .plane
.next_row:
    inc word [row]
    cmp word [row], 16
    jb .row
.done:
    cmp byte [vseg+1], 0A0h
    jne .ret
    call vga_leave
.ret:
    ret

; Fill sbuf (AND) and cbuf (XOR) for the current row and byte window.
build_masks:
    push es
    push ds
    pop es
    mov di, sbuf
    mov cx, [count]
    mov al, 0FFh
    rep stosb
    mov di, cbuf
    mov cx, [count]
    mov al, 0
    rep stosb
    pop es
    mov si, [row]
    shl si, 1
    mov dx, [masks+si]      ; screen mask row
    mov si, [masks+32+si]   ; cursor mask row
    mov bx, [drawn_x]
    mov cx, 16
.pixel:
    test bx, bx
    js .skip
    cmp bx, [width]
    jge .skip
    push cx
    push bx
    mov ax, bx
    mov cl, [bpp_shift]
    shl ax, cl
    mov bx, [first]
    shl bx, 3
    sub ax, bx              ; bit offset in the window
    mov bx, ax
    shr bx, 3               ; byte index
    and al, 7
    mov cl, 8
    sub cl, [bpp]
    sub cl, al              ; shift of the pixel in its byte
    mov al, [pixmask]
    mov ah, al
    and ah, 0Fh             ; white
    shl al, cl
    shl ah, cl
    test dx, 8000h
    jnz .keep
    not al
    and [sbuf+bx], al
.keep:
    test si, 8000h
    jz .nofill
    or [cbuf+bx], ah
.nofill:
    pop bx
    pop cx
.skip:
    shl dx, 1
    shl si, 1
    inc bx
    loop .pixel
    ret

; Save the Graphics Controller registers that the draw depends on and set
; them for write mode 0 and read mode 0. A register is written only when its
; value must change: a write to the mode register makes some adapters show
; one wrong raster line. The mode register keeps its shift and 256-color bits.
gc_indices db 1, 3, 4, 8, 5
gc_keep    db 0, 0, 0, 0, 70h
gc_set     db 0, 0, 0, 0FFh, 0

vga_enter:
    mov dx, 3C4h
    in al, dx
    mov [seq_index], al
    mov al, 2
    out dx, al
    inc dx
    in al, dx
    mov [map_mask], al
    mov dx, 3CEh
    in al, dx
    mov [gc_index], al
    mov si, gc_indices
    mov di, gc_saved
    mov cx, 5
.save:
    mov dx, 3CEh
    lodsb
    out dx, al
    inc dx
    in al, dx
    mov [di], al
    inc di
    mov ah, al
    and ah, [si+4]
    or ah, [si+9]
    cmp ah, al
    je .next
    mov al, ah
    out dx, al
.next:
    loop .save
    ret

vga_leave:
    mov si, gc_indices
    mov di, gc_saved
    mov cx, 5
.restore:
    mov dx, 3CEh
    lodsb
    out dx, al
    inc dx
    in al, dx
    cmp al, [di]
    je .same
    mov al, [di]
    out dx, al
.same:
    inc di
    loop .restore
    dec dx
    mov al, [gc_index]
    out dx, al
    mov dx, 3C4h
    mov al, 2
    out dx, al
    inc dx
    in al, dx
    cmp al, [map_mask]
    je .index
    mov al, [map_mask]
    out dx, al
.index:
    dec dx
    mov al, [seq_index]
    out dx, al
    ret

default_masks:
    dw 3FFFh, 1FFFh, 0FFFh, 07FFh, 03FFh, 01FFh, 00FFh, 007Fh
    dw 003Fh, 001Fh, 01FFh, 10FFh, 30FFh, 0F87Fh, 0F87Fh, 0FC3Fh
    dw 0000h, 4000h, 6000h, 7000h, 7800h, 7C00h, 7E00h, 7F00h
    dw 7F80h, 7C00h, 6C00h, 4600h, 0600h, 0300h, 0300h, 0000h

; ---------------------------------------------------------------------------
; Resident data that is not part of the saved state.

old33       dd 0
old10       dd 0
last_mick_x dw 0
last_mick_y dw 0
mode_key    db 0, 0, 0  ; BIOS mode, rows - 1, columns
vtype       db 0FFh
; The next four bytes come from type_params in this order.
bpp_shift   db 0
planes      db 1
bpp         db 0
pixmask     db 0
interleave  dw 0
vseg        dw 0
stride      dw 0
width       dw 0
height      dw 0
scr_w       dw 640
scr_h       dw 200
xshift      db 0
sbuf        times 16 db 0
cbuf        times 16 db 0
savebuf     times 256 db 0
