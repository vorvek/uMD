; SPDX-FileCopyrightText: 2026 vorvek
; SPDX-License-Identifier: GPL-3.0-only
; Write the DOS memory control block chain, with the upper memory blocks
; linked, to standard output.

bits 16
org 100h
mov sp,ending+256
mov bx,(ending-$$+100h+256+15)/16
mov ah,4ah
int 21h
mov ax,5802h
int 21h
mov [link],al
mov ax,5803h
mov bx,1
int 21h
mov ah,52h
int 21h
mov ax,[es:bx-2]
next:
mov [record],ax
mov es,ax
xor si,si
mov di,record+2
mov cx,16
copy:
mov al,[es:si]
mov [di],al
inc si
inc di
loop copy
mov bx,1
mov cx,18
mov dx,record
mov ah,40h
int 21h
cmp byte [record+2],'Z'
je done
mov ax,[record]
add ax,[record+5]
inc ax
cmp ax,0f000h
jb next
done:
mov ax,5803h
mov bl,[link]
mov bh,0
int 21h
mov ax,4c00h
int 21h
link db 0
record times 18 db 0
ending:
