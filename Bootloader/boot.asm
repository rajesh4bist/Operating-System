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

    mov ax,0
    mov ds,ax
    mov es,ax

    mov ss,ax
    mov sp,0x7c00  

    push es
    push word .after
    retf

.after:


    mov[ebr_drive_number], dl
   


    ;Show loading message
    mov si,msg
    call puts

    ;read drive parameters (sectors per track and head count)
    push es
    mov ah,08h
    int 13h
    jc floppy_error
    pop es

    and cl,0x3F         ;remove top 2 bits
    xor ch,ch
    mov [bdb_sectors_per_track],cx  ;Sector count

    inc dh
    mov[bdb_heads],dh

    ;calculate LBA of root dir = reserved + fats * sectors_per_fat 
    mov ax,[bdb_sectors_per_fat]
    mov bl,[bdb_fat_count]
    xor bh,bh
    mul bx                          ;dx:ax = (fats * sectors_per_fat)
    add ax,[bdb_reserved_sectors]   ;LBA of root dir
    push ax

    ;calculating the size of root dir =  (32 * number_of_entries) / bytes_per_sectors
    mov ax,[bdb_sectors_per_fat]
    shl ax,5
    xor dx,dx
    div word [bdb_bytes_per_sector]     ;no. of sectors to read

    test dx,dx                          ;if dx!=0, add 1
    jz .root_dir_after
    inc ax                              ; if div remainder !=0, inc 1


.root_dir_after:
    mov cl,al                           ;ck = no. of sectors to read
    pop ax                              ;ax = LBA of root dir
    mov dl,[ebr_drive_number]           ;dl = drive no.
    mov bx,buffer
    call disk_read

    ;search for kernel.bin
    xor bx,bx
    mov di,buffer

.search_kernel:
    mov si, file_kernel_bin
    mov cx,11
    push di
    repe cmpsb
    pop di
    je .found_kernel

    add di,32
    inc bx
    cmp bx,[bdb_dir_entries_count]
    jl .search_kernel

    ;if kernel isn't found
    jmp kernel_not_found

.found_kernel:
    mov ax,[di+26]
    mov [kernel_cluster],ax

    ;load FAT from disk to memory
    mov ax, [bdb_reserved_sectors]
    mov bx,buffer
    mov cl,[bdb_sectors_per_fat]
    mov dl,[ebr_drive_number]
    call disk_read
    
    ;read kernel and process FAT chain
    mov bx,KERNEL_LOAD_SEGMENT
    mov es,bx
    mov bx,KERNEL_LOAD_OFFSET

.load_kernel_loop:
    ;read next cluster
    mov ax,[kernel_cluster]               ;first_cluster = (kernel_cluster -2) *  sectors_per_cluster + start_sector
    ;hardcoded value
    add ax,31

    mov cl,1
    mov dl,[ebr_drive_number]
    call disk_read

    add bx,[bdb_bytes_per_sector]

    ;calculate location of next cluster
    mov ax,[kernel_cluster]
    mov cx,3
    mul cx
    mov cx,2
    div cx

    mov si, buffer
    add si,ax
    mov ax,[ds:si]

    or dx,dx
    jz .even 

.odd:
    shr ax,4
    jmp .next_cluster_after

.even:
    and ax,0x0FFF

.next_cluster_after:
    cmp ax,0x0FF8               ;end of chain
    jae .read_finish

    mov [kernel_cluster],ax
    jmp .load_kernel_loop

.read_finish:

    ;jump to kernel
    mov dl,[ebr_drive_number]
    mov ax, KERNEL_LOAD_SEGMENT
    mov ds,ax
    mov es,ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot

    cli 
    hlt

floppy_error:
    mov si,msg_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found:
    mov si, msg_kernel_not_found
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

puts:
    push si
    push ax
    push bx

.loop:
    lodsb
    or al,al
    jz .done

    mov ah,0x0E
    mov bh,0
    int 0x10

    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret
    

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

    ret


disk_reset:
    pusha
    mov ah,0
    stc
    int 13h
    jc floppy_error
    popa
    ret




msg :                   db 'Loading...',ENDL,0
msg_failed :            db 'Disk reading failed' ENDL,0
msg_kernel_not_found:   db 'KERNEL.bin not found',ENDL,0
file_kernel_bin:        db 'KERNEL  BIN'
kernel_cluster:         dw 0 

KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0

times 510-($-$$) db 0            ; pad to 510 bytes
dw 0AA55h                        ;boot signature  

buffer:

