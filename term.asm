; =============================================================================
; Terminal service on UART
; =============================================================================

;-----------------------------------------
; MAKROS
;-----------------------------------------
putspace macro 
        lda     #' '
        jsr     SCI_putc
        endm 

putn    macro
        lda     #$0A    ;'\n'
        jsr     SCI_putc
        endm 

puta    macro 
        jsr     SCI_putb
        @putspace
        endm 

putk    macro   kar
        lda     #~@~
        jsr     SCI_putc
        endm 

puthx   macro
        pshh
        pula
        jsr     SCI_putb
        txa
        jsr     SCI_putb
        @putspace
        endm 


;-----------------------------------------
; STRINGS
;-----------------------------------------
startstrt
        db      " Push t button for terminal!",$0A,0
warn1str
        db      $0A,"Warning! Half byte gived as last byte, missing 4 bits forced to 0.",$0A,0
helpstr 
        db      $0A,"Serial terminal. Here is some help:",$0A
        db      "? : This help.",$0A
        db      "i : Print MCU ID.",$0A
        db      "dAAAA : Dump from address AAAAh (Default 0000h).",$0A
        db      "n : Next (Dump).",$0A
        db      "b : Back (Dump).",$0A
        db      "a : Again (Dump).",$0A
        db      "eAAAA : Erase page from address AAAAh (128 bytes).",$0A
        db      "hAAAA11223344 [ENTER] : Hexa write from address AAAAh,",$0A
        db      "sAAAAwww.butyi.hu [ENTER] : String write from address AAAAh,",$0A
        db      "r or x : Reset (Exit).",$0A,0
err00
        db      "OK",0
err10
        db      "Error! Access erro",0
err20
        db      "Error! Protection violation",0
err50
        db      "Error! Length zero",0
err60
        db      "Error! Length high",0
errA0
        db      "Error! Bootloader area",0
errB0
        db      "Error! Boundary violation",0

TERM_Init
        ldhx    #startstrt
        jsr     SCI_puts 
        rts

egetkey
        ;loop when waiting for a terminal character
        jsr     RTC_Handle
        
        ; Check if timeout elapsed (user didn't do anything in the last 8s)
        tst     comtimer
        bne     egk_nto         ; Jump through on timeout handling
        ; Timeout handling: Simulate pushed 'r' button to leave terminal
        bra     term_reset
egk_nto ;No timeout
        
        jsr     SCI_getc	; Check character from useer
        bcc     egetkey		; No character arrived, wait further
        mov     #LONGWAIT,comtimer      ; Character arrived, pull up timer

        cmp     #$0D            ; Windows ENTER
        beq     egk_noecho
        ; Change Linux ENTER key to Windows ENTER key
        cmp     #$0A            ; Linux ENTER
        bne     egk_enter
        lda     #$0D            ; Windows ENTER
        bra     egk_noecho
egk_enter        
        jsr     SCI_putc        ; Echo back the pushed key
egk_noecho
        tsta			; Set CCR to be able to use conditional branches after return
        rts


;Serial terminal
terminal
        lda     BLCR            ; BootLoader Configuration Register
        and     #BLCR_ET_       ; Check if terminal is enabled
        jeq     main_loop       ; if not enabled, do return from terminal
        mov     #LONGWAIT,comtimer ; Pull up timer
term_help
        ldhx    #helpstr
        jsr     SCI_puts
term_cikl
        @putn
term_cikl_l
        jsr     LED_Off
        bsr     egetkey
        jsr     LED_On
        cmp     #'x'
        beq     term_reset
        cmp     #'r'
        beq     term_reset
        cmp     #'d'
        beq     term_dump
        cmp     #'n'
        beq     term_dump_n
        cmp     #'a'
        beq     term_dump_a
        cmp     #'b'
        beq     term_dump_b
        cmp     #'?'
        beq     term_help
        cmp     #'s'
        @jeq    term_string
        cmp     #'h'
        @jeq    term_hexa
        cmp     #'e'
        @jeq    term_erase
        cmp     #'i'
        @jeq    term_id

        
        bra     term_cikl_l

term_reset                      ; MCU reset
        cli                     ; Enable interrupts
        db      $8D             ; Not existing opcode to force illegal opcode reset

term_dump_b
        dec     dump_addr       ; Mod high byte by 1 to change address by 256
term_dump_a
        dec     dump_addr       ; Mod high byte by 1 to change address by 256
        bra     term_dump_n
term_dump
        jsr     getdumpaddr
term_dump_n                     ; continue
        clr     dump_addr+1     ; Dump always from begin of 256 byte long page
        ldhx    dump_addr
        bsr     dump8lines
        @putn
        bsr     dump8lines
        @putn
        sthx    dump_addr
        bra     term_cikl


dump8lines
        lda     #8
td_c1
        psha
        bsr     dumpline
        pula
        dbnza   td_c1
        rts

dumphn                  	; Dump Hexa n-times
	psha
        lda     ,x
        jsr     SCI_putb
        aix     #1
        pula
        dbnza	dumphn
        rts

dumpline
        @putn
        pshh
        pula    
        jsr     SCI_putb
        txa
        jsr     SCI_putb
        lda     #':'
        jsr     SCI_putc
        @putspace
        lda	#4
        bsr     dumphn
        @putspace
        lda	#4
        bsr     dumphn
        @putspace
        @putspace
        lda	#4
        bsr     dumphn
        @putspace
        lda	#4
        bsr     dumphn
        
        @putspace
        lda     #'|'
        jsr     SCI_putc
        @putspace

        aix     #-16
        lda	#8
        bsr     dumpan
        @putspace
        lda	#8
        bsr     dumpan
        rts

dumpan                   ;Dump ascii n-times
        psha
        lda     ,x
	; If character is not displayable, print dot
        cmp     #$20
        blo     pr_dot
        cmp     #$7F
        bhi	pr_dot
        bra     pr_ch
pr_dot
        lda     #'.'
pr_ch
        jsr     SCI_putc
        aix     #1

        pula
        dbnza   dumpan
        rts

; Read string from user till ENTER key
getstringdata
        ; Check if data is not too long
        ldx     wr_datac
        cpx     #$7F
        @req
        
        jsr     egetkey         ; Read a character from user
        cmp     #$0d            ; Windows enter
        @req

        bsr     getdata_next
        bra     getstringdata

getdata_next
        ldhx    wr_datat        ; Load buffer pointer as index
        sta     ,x              ; Write character to buffer
        ; Increase length
        inc     wr_datac        
        
        ; Increase pointer
        ldhx    wr_datat
        aix     #1
        sthx    wr_datat
        
        rts

term_common
        clr     wr_datac        ; Clear length of write
        ldhx    #wr_data        ; Copy buffer address
        sthx    wr_datat        ;  to pointer variable
        jsr     getdumpaddr     ; Read address from user
        rts

; String write into flash
term_string
        bsr     term_common     ; Call common part of terminal write
        bsr     getstringdata   ; Read string data from user
        bra     term_write      ; Jump to write

; Hexa data write into flash or RAM
term_hexa
        bsr     term_common     ; Call common part of terminal write
        jsr     gethexdata      ; Read hexa data from user

        ; End of communication, now do nome checks on given parameters
term_write
        ; Check if is there any data to be written
        ldx     wr_datac
        @jeq    term_cikl       ; If no, jump back to main menu

        ; Write data into flash
        ; Source address doesn't matter for erase
        ldhx    #wr_data
        pshx                    ; lo
        pshh                    ; hi
        ; Target address
        ldhx    dump_addr
        pshx                    ; lo
        pshh                    ; hi
        ; Length to be zero for erase
        ldx     wr_datac
        pshx                    ; lo
        clrh
        pshh                    ; hi
        jsr     MEM_doit        ; call
        ais     #6              ; release 6 byte parameters
        bsr     printmemresp
 
        ; Print dump to verify write was successfull  
        jmp     term_dump_n


printmemresp
        psha
        @putn
        pula        
        tsta
        bne     pmr_10
        ldhx    #err00
        jsr     SCI_puts
        rts
pmr_10
        cmp     #$10
        bne     pmr_20
        ldhx    #err10
        jsr     SCI_puts
        rts
pmr_20
        cmp     #$20
        bne     pmr_50
        ldhx    #err20
        jsr     SCI_puts
        rts
pmr_50
        cmp     #$50
        bne     pmr_60
        ldhx    #err50
        jsr     SCI_puts
        rts
pmr_60
        cmp     #$60
        bne     pmr_A0
        ldhx    #err60
        jsr     SCI_puts
        rts
pmr_A0
        cmp     #$A0
        bne     pmr_B0
        ldhx    #errA0
        jsr     SCI_puts
        rts
pmr_B0
        cmp     #$B0
        bne     pmr_end
        ldhx    #errB0
        jsr     SCI_puts
pmr_end
        rts
        
; Erase page from terminal
term_erase
        ; Read address
        bsr     getdumpaddr
        
        ; Erase flash page
        ; Source address doesn't matter for erase
        ldhx    #0
        pshx                    ; lo
        pshh                    ; hi
        ; Target address
        ldhx    dump_addr
        pshx                    ; lo
        pshh                    ; hi
        ; Length to be zero for erase
        ldhx    #$0000
        pshx                    ; lo
        pshh                    ; hi
        jsr     MEM_doit        ; call
        ais     #6              ; release 6 byte parameters
        bsr     printmemresp

        ; Print dump to verify erase was successfull  
        jmp     term_dump_n

; Read hexa bytes from user till ENTER key
gethexdata
        ; Check if data is not too long
        ldx     wr_datac
        cpx     #$7F
        @req
        
        jsr     egetkey         ; Read a character from user
        cmp     #$0d            ; Windows enter
        @req
        bsr     convtoval       ; Convert character to 4 bits binary value
        nsa                     ; Shift up by 4 bits
        psha                    ; Save high nibble
        jsr     egetkey         ; Read a character from user
        cmp     #$0d            ; Windows enter
        bne     ghd_noenter
        ldhx    #warn1str       ; Here cannot exit, half byte was given
        jsr     SCI_puts
        clra                    ; Not given 4 bits to be zero
        bra     ghd_mergenibbles        
ghd_noenter        
        bsr     convtoval       ; Convert character to 4 bits binary value
ghd_mergenibbles
        ora     1,sp            ; Binary or with high nibble to have all 8 bits of data byte
        ais     #1              ; Drop out high nibble from stack
        jsr     getdata_next

        bra     gethexdata

term_id
        lda     ECUID           ; Load ID of ECU 
        jsr     SCI_putb
        jmp     term_cikl

; Convert character to 4 bits binary value
convtoval
        sub     #48
        bmi     ctv_0
        cmp     #10
        blo     ctv_x
        sub     #7
        bmi     ctv_0
        cmp     #10
        blo     ctv_0
        cmp     #16
        blo     ctv_x
        sub     #32
        bmi     ctv_0
        cmp     #10
        blo     ctv_0
        cmp     #16
        blo     ctv_x
ctv_0
        clra
ctv_x
        and     #$0F
        rts

getdumpaddr
        jsr     egetkey
        bsr     convtoval       ; Convert character to 4 bits binary value
        nsa
        sta     dump_addr

        jsr     egetkey
        bsr     convtoval       ; Convert character to 4 bits binary value
        ora     dump_addr
        sta     dump_addr

        jsr     egetkey
        bsr     convtoval       ; Convert character to 4 bits binary value
        nsa
        sta     dump_addr+1

        jsr     egetkey
        bsr     convtoval       ; Convert character to 4 bits binary value
        ora     dump_addr+1
        sta     dump_addr+1
        rts





