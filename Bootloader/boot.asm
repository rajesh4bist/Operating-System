org 0x7c00 ;BIOS loads bootloader here
bits 16 

%define ENDL 0x0D, 0x0A

; FAT12 header

jmp short start 
nop

bdb_oem:                    db 'MSWIN4.1'      ;8 bytes
bdb_bytes_per_sector:        dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0e0h
bdb_total_sectors:          dw 2880            ;2880*512 = 1.44MB
bdb_media_descriptor_type:  db 0f0h            ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18              ; 9 sectors per fat
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_scetor_count:     dd 0


;extended boot record

ebr_drive_number:           db 0                   ;0x00 = floppy, 0x80 = hdd,..useless
                            db 0                   ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h  ; serial number
ebr_volume_label:           db 'OS'                ; 11 bytes
ebr_system_id:              db 'FAT12'             ; 8 bytes


;
;----------CODE-------------
;


start:
    jmp main


puts:
    push si
    push ax
    push bx

.loop:
    lodsb           ;load next character in al
    or al,bl
    jz .done

    mov ah,0x0e      ;bios interrupt
    mov bh,0 
    int 0x10

    jmp .loop

.done:
    pop ax
    pop si
    ret 

main:
    mov ax,0
    mov ds,ax
    mov es,ax

    mov ss,ax
    mov sp,0x7c00  

    mov[ebr_drive_number], dl
    mov ax,1                        ;LBA=1, second sector from disk
    mov cl,1                        ; 1 sector to read
    mov bx,0x7e00
    call disk_read



    mov si,msg
    call puts

    cli 
    hlt

floppy_error:
    mov si,msg_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah,0
    int 16h                         ;waits for keypress
    jmp 0FFFFh:0                    ;jump to beginning of Bios

    hlt

.halt:
    cli                             ;disable interrupts
    hlt   

;Floppy disk routines
;LBA to CHS addressing

;ax:LBA address
;cx bits[0-5]: sector number 
;cx bits[6-15]: cylinder


lba_to_chs:

    push ax
    push dx

    xor dx,dx
    div word [bdb_sectors_per_track]  
                                          ;dx =LBA % SectorsPerTrack
    inc dx                                ;dx = (LBA % SectorsPerTrack + 1) = sector  
    mov cx,dx                             ;cx = sector

    xor dx,dx                             ;ax = (LBA / SectorsPerTrack) / Heads = cylinder
    div word[bdb_heads]                   ;dx = ( LBA / SectorsPerTrack) % Heads = head

    mov dh,dl                             ;dh = head
    mov ch,al                             ;ch = cylinder (8 lower bits)
    shl ah,6
    or cl,ah

    pop ax
    mov dl,al
    pop ax
    ret


;Reading from disk
    ; - ax : LBA addr
    ; - cl : no. of sectors to read 
    ; - dl : drive no.
    ; - es:bx: memory addr to store read data

disk_read:

    push ax                ;saving modifying registers
    push bx 
    push cx
    push dx
    push di

    push cx
    call lba_to_chs         ;calculate CHS
    pop ax                  ; al = no. of sectors to read

    mov ah, 02h
    mov di,3

.retry:
    pusha                   ; save all registers
    stc                     ; set carry flag
    int 13h
    jnc .done

    ;call failed

    popa
    call disk_reset

    dec di
    test di,di
    jnz .retry

.fail:
    ;after all attempts are failed
    jmp floppy_error

.done:
    popa

    pop di             ;restore modified registers
    pop dx
    pop cx
    pop bx
    pop ax


disk_reset:
    pusha
    mov ah,0
    stc
    int 13h
    jc floppy_error
    popa
    ret




msg : db 'Hello world',ENDL,0
msg_failed : db 'Disk reading failed' ENDL,0

times 510-($-$$) db 0            ; pad to 510 bytes
dw 0AA55h                        ;boot signature  

