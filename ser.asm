; =============================================================================
; SCI protocol for MC9S08DZ60 Bootloader
; =============================================================================


        #RAM



        #ROM

dlc_read
        jsr     readaddress     ; Read address high and low byte
        jsr     scigetct	; Timeout type getc to have length of read
        beq     rd_lennull      ; Check if lenth is zero
        sta     wr_datac        ; Save length
        jsr     addcs
        ldhx    dump_addr
        jsr     SCI_anshead
rd_loop
        lda     ,x
        jsr     SCI_putc
        jsr     addcs
        aix     #1
        dbnz    wr_datac,rd_loop
        lda     checksum        
        jsr     SCI_putc
        jmp     main_time       ; Loop again with pull up timer
rd_lennull
        lda     #$05            ; error code of zero lentgh write
        jsr     SCI_anserr
        jmp     main_time       ; Loop again with pull up timer

; Task to handle serial binary frame
serialtask
        ; Read second frame byte
        jsr     scigetct	; Timeout type getc
        cmp     #$DA            ; Check if second expected frame byte received
        jne     main_time       ; Not, wait for next frame

        ; Read target SA byte (should be ECU ID to accept request, but I skip it now)
        jsr     scigetct	; Timeout type getc
        cmp     ECUID
        beq     st_idok
        cmp     #$FF
        jne     main_time       ; Wait for next frame
        jmp     st_bcid         ; Broad Cast ID
st_idok
        ; Read source SA byte of requester tool
        jsr     scigetct	; Timeout type getc
        sta     diag_sa         ; To be saved as diag SA for answer

        ; Read command byte (DLC on CAN)
        jsr     scigetct	; Timeout type getc
        beq     dlc_tp          ; 0 = Tester Present
        cbeqa   #1,dlc_req      ; 1 = Request
        cbeqa   #2,dlc_erase    ; 2 = Erase
        cbeqa   #3,dlc_read     ; 3 = Read
        cbeqa   #4,dlc_write    ; 4 = Write
        cbeqa   #6,dlc_fp       ; 6 = FingerPrint
        bra     errcodeuc       ; Other = Command error
dlc_fp
        jmp     dlc_fngprnt
dlc_req
        bsr     scigetct	; Timeout type getc to read request code
        cmp     #$52            ; RUN command ('R')
        jeq     application     ; Run application immediately
        cmp     #$11            ; MCU reset code
        bne     errcodeus       ; Only reset (0x11) is suported
        db      $AC             ; Illegal opcode to reset MCU

dlc_tp  ; Tester Present
        jsr     SCI_ansnull     ; Send answer without data
        jmp     main_time       ; Loop again with pull up timer

timeouterr
        lda     #$0E            ; Timeout
        bra     errcoden
errcodeuc
        lda     #$07            ; Unknown command or DLC
        bra     errcoden
errcodeus
        lda     #$08            ; Unknown service
errcoden
        jsr     SCI_anserr	; Send answer
        jmp     main_time       ; Loop again with pull up timer

readaddress
        clr     checksum
        bsr     scigetct	; Timeout type getc to read address high byte
        sta     dump_addr       ; Hi
        jsr     addcs
        bsr     scigetct	; Timeout type getc to read address low byte
        sta     dump_addr+1     ; Lo
        jsr     addcs
        rts
dlc_erase
        bsr     readaddress
        clr     wr_datat        ; Length for erase NVM is always 0
        jsr     nvm_doit        ; Do the erase
        bsr     SCI_anserr      ; Report error code
        jmp     main_time       ; Loop again with pull up timer
dlc_write
        bsr     readaddress     ; Read address high and low byte
        bsr     scigetct	; Timeout type getc to read length of write
        beq     wr_lennull      ; Check if lenth is zero
        bmi     wr_lenlarge     ; Check if lenth is too large
        sta     wr_datac        ; Save length for data read
        sta     wr_datat        ; Save length for write NVM
        jsr     addcs
        bsr     scigetct	; Timeout type getc to reserved byte for timeout
        jsr     addcs
        ldhx    #wr_data        ; Address of RAM buffer
wr_loop
        bsr     scigetct	; Timeout type getc to read data to be written
        sta     ,x              ; Write data into RAM buffer 
        jsr     addcs
        aix     #1              ; increment RAM buffer index
        dbnz    wr_datac,wr_loop
            
        bsr     scigetct	; Timeout type getc to read checksum
        cmp     checksum        ; Check the checksum
        bne     wr_cserr
        jsr     nvm_doit        ; Do the write
        bsr     SCI_anserr      ; Report error code, it is zero if success
        jmp     main_time       ; Loop again with pull up timer
wr_lennull
        lda     #$05            ; error code of zero lentgh write
        bra     wr_answ
wr_lenlarge
        lda     #$06            ; error code of too large lentgh write
        bra     wr_answ
wr_cserr
        lda     #$0C            ; error code of checksum
        bsr     SCI_anserr
wr_answ        
        jmp     main_time

; Wait a character on UART till timeout 
scigetct
        @tim
scigetctc
        jsr     RTC_Handle
        beq     scigetcto       ; Timeout handling
        jsr     SCI_getc
        bcc     scigetctc       ; If no character, wait more
        rts                     ; Character received
scigetcto                       ; Timeout handling
        ais     #2              ; Drop out saved return address of scigetct from stack, there will be no return 
        bra     timeouterr      ; Instead of return, jump directly to send timeout response 


; Send answer header back to client
SCI_anshead
        lda     #$1C
        jsr     SCI_putc
        lda     #$DA
        jsr     SCI_putc
        lda     diag_sa
        jsr     SCI_putc
        lda     ECUID 
        jsr     SCI_putc
        rts

SCI_anserr
        psha                    ; Save error code
        bsr     SCI_anshead
        lda     #1              ; Length of data
        jsr     SCI_putc
        pula                    ; Get error code
        jsr     SCI_putc         
        rts

SCI_ansnull
        bsr     SCI_anshead
        lda     #0              ; Length 0, no data
        jsr     SCI_putc
        rts
st_bcid ; BroadCast ID handling
        bsr     scigetct	; Timeout type getc to read tool ID
        sta     diag_sa         ; To be saved as diag SA for answer
        bsr     scigetct	; Timeout type getc to read DLC (Command)
        cmp     #7              ; Check if Set ECU ID by serialnum
        beq     bcsetid         ; BroadCast Set ID
        cmp     #1              ; Check if Instruction
        jne     errcodeuc       ; Command error        
        bsr     scigetct	; Timeout type getc to read request code
        cmp     #$22            ; Scan Network request
        jne     errcodeus       ; Only Scan Network request is suported
        bsr     SCI_anshead
        lda     #7              ; DLC=7
        jsr     SCI_putc
        mov     #6,wr_datac     ; Set length to be sent
        ldhx    #SERIAL_NUMBER  ; Source address of sent data from
cn_loop                         ; Send back serial number bytes
        lda     ,x
        jsr     SCI_putc
        aix     #1
        dbnz    wr_datac,cn_loop

        lda     ECUID           ; Send back current ECUID
        jsr     SCI_putc

        jmp     main_time

bcsetid ; BroadCast Set ECUID
        mov     #6,wr_datac     ; Set length to be sent
        ldhx    #SERIAL_NUMBER  ; Source address of sent data from
bcsetid_loop        
        bsr     scigetct	; Timeout type getc to read next serial number byte 
        cmp     ,x              ; Check serial number byte
        jne     main_time       ; Skip if not match (No answer needed)
        aix     #1
        dbnz    wr_datac,bcsetid_loop
                                ; Here software comes only if serial number was marched, this ECU ID shall be updated
        jsr     scigetct	; Timeout type getc to read new ECUID
        sta     wr_data         ; Save new ECUID into data buffer for write
        lda     ECUID+1         ; Load original update counter
        inca                    ; increase by one
        sta     wr_data+1       ; Save back into buffer
        mov     #6,wr_datac     ; Set length of copy
        clrhx                   ; Clear index of copy
bcsetid_cpy        
        lda     FINGERPR,x      ; Load fingerprint byte
        sta     wr_data+2,x     ; Save into buffer
        aix     #1
        dbnz    wr_datac,bcsetid_cpy
        ldhx    #ECUID          ; Load address of ECUID
        sthx    dump_addr       ; Save as target address
        clr     wr_datat        ; Set length zero for erase first
        jsr     nvm_doit_fpok   ; Erase ECUID in EEPROM, no fingerprint needed
        bne     bcsetid_reasp   ; In case of error, no more task
        ldhx    #ECUID          ; Load address of ECUID
        sthx    dump_addr       ; Save as target address
        mov     #8,wr_datat     ; Set length to 2 to Write
        jsr     nvm_doit_fpok   ; Write new ECUID, no fingerprint needed
bcsetid_reasp
        jsr     SCI_anserr      ; Send answer back
        jmp     main_time

dlc_fngprnt
        clr     fp_cs           ; Clear checksum
        mov     #6,wr_datac     ; Set length to read fingerprint bytes
        ldhx    #wr_data        ; Buffer to read bytes
fngprnt_loop
        jsr     scigetct	; Timeout type getc to read next fingerprint byte 
        sta     ,x              ; Save fingerprint byte
        add     fp_cs
        sta     fp_cs           ; Add received byte value to checksum 
        aix     #1
        dbnz    wr_datac,fngprnt_loop
        lda     FINGERPR+6      ; Load original update counter
        inca                    ; increase by one
        sta     ,x              ; Save back into buffer
        add     fp_cs
        sta     fp_cs           ; Add update counter value to checksum 
        aix     #1
        lda     fp_cs           ; Load checksum of prevoius 7 bytes
        sta     ,x              ; Save back into buffer

        ldhx    #FINGERPR       ; Load address of fingerprint
        sthx    dump_addr       ; Save as target address
        clr     wr_datat        ; Set length zero for erase first
        jsr     nvm_doit_fpok   ; Erase fingerprint in EEPROM, no fingerprint needed
        bne     fngprnt_reasp   ; In case of error, no more task
        ldhx    #FINGERPR       ; Load address of fingerprint
        sthx    dump_addr       ; Save as target address
        mov     #8,wr_datat     ; Set length to 2 to Write
        jsr     nvm_doit_fpok   ; Write new fingerprint, no fingerprint needed
fngprnt_reasp
        bne     fngprnt_err     ; Jump if fingerprint write was not successful
        mov     #1,fpavail      ; Set flag if fingerprint is written well 
fngprnt_err
        jsr     SCI_anserr      ; Send answer back
        jmp     main_time

