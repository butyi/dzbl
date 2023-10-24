; =============================================================================
; CAN communication of Bootloader for 9S08DZ60
; =============================================================================

        #RAM
can_datalen     ds      1  	; Number of data byte to be waiting for from CAN (if not null, write is ongoing)
can_cserr       ds      1  	; Checksum error flag
can_derr        ds      1  	; Data error flag
packetnumber    ds      1       ; Count number of received data packets for checksum calculation

can_idin        ds      4  	; 4 byte buffer for CAN ID calculation input in simple ID 
can_idout       ds      4  	; 4 byte buffer for CAN ID calculation output with register bit mapping 

        #ROM


; EECANBTR0 (EECANBAUD+0): SJW = 1...4 Tq, Prescaler value = 1...64.
; EECANBTR1 (EECANBAUD+1): Sample per bit = 1 or 3, Tseg2 = 1...8 Tq, Tseg1 = 1...16 Tq
; Baud = fCANCLK / Prescaler / (1 + Tseg1 + Tseg2)
; Sample point = (1 + Tseg1)/(1 + Tseg1 + Tseg2)
can_config      ; Config in EEPROM.
        org     EECANBAUD       
;        db      $00,$01         ; Baud = 4MHz / 1 / (1+2+1) = 1M.    Sample point = (1+2)/(1+2+1) = 75%
        db      $00,$05         ; Baud = 4MHz / 1 / (1+6+1) = 500k.  Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 1M with fQuarz=8MHz)
;        db      $01,$05         ; Baud = 4MHz / 2 / (1+6+1) = 250k.  Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 500k with fQuarz=8MHz)
;        db      $03,$05         ; Baud = 4MHz / 4 / (1+6+1) = 125k.  Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 250k with fQuarz=8MHz)
;        db      $07,$05         ; Baud = 4MHz / 8 / (1+6+1) = 62.5k. Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 125k with fQuarz=8MHz)
        org     can_config

; ------------------------------------------------------------------------------
; Freescale Controller Area Network (S08MSCANV1)
; Set up CAN for 500 kbit/s using 4 MHz external clock
CAN_Init
        ; MSCAN Enable, CLKSRC=0 use ext osc, BORM=0 auto busoff recovery, SLPAK=0 no sleep
        lda     #CAN_CANE_      ; Auto BusOff recovery
        sta     CANCTL1

        jsr     CAN_ChkInitMode
        ais     #-2             ; Reserve two bytes in stack for baud rate bytes 

        ; Check two bytes in EEPROM. If any has value $FF, both to be forced to valid 500kbaud value.
        clrx
        lda     EECANBAUD+0     ; Read value from EEPROM
        sta     1,sp            ; Save value for later use
        coma                    ; convert $FF to $00
        bne     can_btr_0_ok    ; jump id not zero, fo value is not $FF
        incx                    ; Count number of $FF value in X 
can_btr_0_ok
        lda     EECANBAUD+1     ; Read value from EEPROM
        sta     2,sp            ; Save value for later use
        coma                    ; convert $FF to $00
        bne     can_btr_1_ok    ; jump id not zero, fo value is not $FF
        incx                    ; Count number of $FF value in X 
can_btr_1_ok
        tstx                    ; update CCR with value of X
        beq     can_btr_ok      ; jump if there was no $FF value in EEPROM
        clr     1,sp            ; Default 500kbaud value 
        lda     #$05            ; Default 500kbaud value 
        sta     2,sp
can_btr_ok
        bne     can_btr_0_ok
        clra                    ; Default 500kbaud value 

        ; SJW = 1...4 Tq, Prescaler value = 1...64
        lda     1,sp
        sta     CANBTR0
        
        ; One sample per bit, Tseg2 = 1...8 Tq, Tseg1 = 1...16 Tq
        lda     2,sp
        sta     CANBTR1

        ais     #2              ; Free up two baud rate bytes from stack  

        ; Acceptance filter for Rx
        clra
        sta     CANIDAC         ; Two 32-bit acceptance filters

        ; 0-3: 1CDA0B55 (target specific), 4-7: 1CDAFF55 (broadcast)
        ldhx    #$1CDA
        sthx    can_idin
        lda     ECUID
        sta     can_idin+2
        clr     can_idin+3     ; Source address (diag tool, can be any value, doesn't matter here)
        jsr     CAN_CalcID
        ldhx    can_idout
        sthx    CANIDAR0
        ldhx    can_idout+2
        sthx    CANIDAR2

        lda     #$FF
        sta     can_idin+2
        bsr     CAN_CalcID        
        ldhx    can_idout
        sthx    CANIDAR4
        ldhx    can_idout+2
        sthx    CANIDAR6

        clra                    ; Only this meesage
        sta     CANIDMR0
        sta     CANIDMR1
        sta     CANIDMR4
        sta     CANIDMR5
        lda     #$01            ; Accept any source address (mask 0x01)
        sta     CANIDMR2
        sta     CANIDMR6
        lda     #$FE            ; Accept any source address (mask 0xFE)
        sta     CANIDMR3
        sta     CANIDMR7

        clr     can_datalen
CAN_exitinit
        ; Leave Initialization Mode
        clra
        sta     CANCTL0

        ; Wait for exit Initialization Mode Acknowledge
ican2
        lda     CANCTL1
        and     #CAN_INITAK_
        bne     ican2
        
        rts

CAN_GoInitMode
        ; Request init mode
        lda     #CAN_INITRQ_
        sta     CANCTL0
CAN_ChkInitMode
        ; Wait for Initialization Mode Acknowledge
        lda     CANCTL1
        and     #CAN_INITAK_
        beq     CAN_ChkInitMode
        rts

CAN_Deinit
        bsr     CAN_GoInitMode
        ; Reset value into all registers
        lda     #$01
        sta     CANCTL0
        lda     #$11
        sta     CANCTL1
        lda     #$07
        sta     CANTFLG
        sta     CANTBSEL
        clra
        sta     CANBTR0
        sta     CANBTR1
        sta     CANRFLG
        sta     CANRIER
        sta     CANTIER
        sta     CANTARQ
        sta     CANIDAC
        sta     CANMISC
        bra     CAN_exitinit

; Calculate ID register bytes from simple 29bit value
CAN_CalcID
        ; simple 29 bits        6,sp        5,sp        4,sp        3,sp
        ;                       ---3 3333   2222 2222   1111 1111   0000 0000
        ; register bytes
        ;                       3333 3222   222s i221   1111 1110   0000 000r
        ldhx    can_idin
        lslhx
        lslhx
        lslhx
        pshh
        pula
        sta     can_idout
        
        ldhx    can_idin+1
        lslhx
        pshh
        lda     1,sp
        and     #$07
        sta     can_idout+1
        pula
        lsla
        lsla
        and     #$E0
        ora     can_idout+1
        ora     #$18            ; Set SSR and IDE bits
        sta     can_idout+1
        
        ldhx    can_idin+2
        lslhx
        pshh
        pula
        sta     can_idout+2
        stx     can_idout+3     ; Leave RTR bit null

        rts

CAN_RxHandler
        ; Save diag source address for answer target
        lda     CANRIDR2
        rora                    ; shift MSB (mask 0x01) into carry
        lda     CANRIDR3
        rora                    ; shift right: drop out RTR (mask 0x01), move carry into MSB (mask 0x80)
        sta     diag_sa
        
        lda     CANIDAC         ; Check which acceptance hit happened (0 target specific, 1 broadcast)
        and     #CAN_IDHIT2_|CAN_IDHIT1_|CAN_IDHIT0_
        jne     cr_broadcast

        ; Target specific, all services available
        lda     CANRDLR         ; Check DLC (the command actually)
        and     #CANR_DLC3_|CANR_DLC2_|CANR_DLC1_|CANR_DLC0_
        beq     cr_tp           ; Tester Present
        cmp     #1
        beq     cr_req          ; Request
        cmp     #2
        beq     cr_erase        ; Erase memory
        cmp     #3
        jeq     cr_read         ; Read memory
        cmp     #4
        beq     cr_write        ; Write memory
        cmp     #6
        jeq     cr_wrfp         ; Write fingerprint
c_errcodeuc        
        lda     #$07            ; Unknown command or DLC
        jsr     CAN_anserr
        rts

cr_tp
        jsr     CAN_ansnull
        rts
cr_req
        lda     CANRDSR0        ; Check service
        cmp     #$52            ; RUN command ('R')
        jeq     application     ; Run application immediately
        cmp     #$11            ; ECU reset
        bne     c_errcodeus
        db      $AC             ; Illegal opcode to reset MCU
c_errcodeus
        lda     #$08            ; Unknown subservice
        jsr     CAN_anserr
        rts

cr_erase
        jsr     can_readaddr
        clr     wr_datat        ; Length for erase NVM is always 0
        jsr     nvm_doit        ; Do the erase, return value is 0 if success
        jsr     CAN_anserr      ; Report error or success code 
        rts

cr_lenlarge
        lda     #$06            ; error code of too large lentgh write
        bra     cr_ans
cr_lennull
        lda     #$05            ; error code of zero lentgh write
cr_ans        
        jsr     CAN_anserr
        rts

cr_write
        clr     can_cserr
        clr     can_derr
        jsr     can_readaddr
        lda     CANRDSR2        ; length
        beq     cr_lennull      ; Check if lenth is zero
        bmi     cr_lenlarge     ; Check if lenth is too large
        sta     wr_datat        ; Save length for write NVM
        psha
        inca                    ; Reserve one additional byte for checksum
        sta     can_datalen     ; Save length for data reception (ongoing write)
        pula
        jsr     addcs
        clr     packetnumber    ; Clear packet number
        jsr     CAN_AckRx
        tim                     ; pull up timer
        ldhx    #wr_data        ; Address of RAM buffer
        lda     #1
        sta     wr_data
        inca
        sta     wr_data+1
crw_dataloop                    ; Wait here for next data message
        jsr     RTC_Handle
        beq     crw_timeout     ; Jump if time spent
        
        lda     CANRFLG         ; Check if CAN message received
        and     #CAN_RXF_
        beq     crw_dataloop    ; Wait if not
        
        tim                     ; pull up timer
        lda     CANRDLR         ; Check DLC (the command actually)
        and     #CANR_DLC3_|CANR_DLC2_|CANR_DLC1_|CANR_DLC0_
        cmp     #8              ; Data frame
        bne     crw_ndferr      ; Not data frame error
        
        lda     CANRDSR0        ; Here is data frame, process it
        bsr     CAN_pnd
        lda     CANRDSR1
        bsr     CAN_pnd
        lda     CANRDSR2
        bsr     CAN_pnd
        lda     CANRDSR3
        bsr     CAN_pnd
        lda     CANRDSR4
        bsr     CAN_pnd
        lda     CANRDSR5
        bsr     CAN_pnd
        lda     CANRDSR6
        bsr     CAN_pnd
        lda     CANRDSR7
        bsr     CAN_pnd
        ; CS EOR packetnumber to detect data packet order change 
        inc     packetnumber
        lda     checksum
        eor     packetnumber
        sta     checksum
crw_procdone
        jsr     CAN_AckRx
        lda     can_datalen     ; Check if all data was sent
        beq     crw_dowrite     ; If yes, do write
        bra     crw_dataloop    ; Wait for more data message
crw_dowrite
        tst     can_cserr
        bne     crw_cserr
        tst     can_derr
        bne     crw_derr
        jsr     nvm_doit        ; Do the write, return value is 0 if success
        jsr     CAN_anserr      ; Report error or success code 
        rts
crw_cserr
        lda     #$0C            ; Checksum error code
        jsr     CAN_anserr
        rts
crw_timeout
        lda     #$0E            ; Timeout
        jsr     CAN_anserr
        rts
crw_derr
        lda     #$0D            ; data error code
        jsr     CAN_anserr
        rts
crw_ndferr
        lda     #$02            ; Protocol violation
        jsr     CAN_anserr
        rts

CAN_pnd
        psha
        lda     can_datalen     ; Check if all data was sent
        beq     cpnd_nodata
        cmp     #1
        beq     cpnd_checksum
        lda     1,sp
        sta     ,x
        jsr     addcs
        aix     #1              ; Point to next data
        dec     can_datalen     ; Administrate one data byte processed
        bra     cpnd_fdok
cpnd_checksum
        lda     1,sp
        sub     checksum
        sta     can_cserr
        dec     can_datalen     ; Administrate one data byte processed
        bra     cpnd_fdok
cpnd_nodata
        lda     1,sp            ; Load not used byte
        cmp     #$FB            ; Check if filler byte is used
        beq     cpnd_fdok       ; Filler Data OK
        mov     #1,can_derr
cpnd_fdok
        ais     #1              ; Drop stack data
        rts

cr_read
        bsr     can_readaddr
        lda     CANRDSR2        ; length
        jsr     CAN_AckRx
        jeq     cr_lennull      ; Check if lenth is zero
        jmi     cr_lenlarge     ; Check if lenth is too large
        psha
        inca                    ; Reserve one additional byte for checksum
        sta     can_datalen
        pula
        jsr     addcs
        clr     packetnumber    ; Clear packet number
;        bsr     CAN_ansok       ; Do not send positive response, data will show it
        ldhx    dump_addr       ; Load address of data to be send
crr_loop
        bsr     CAN_SendData    ; Send 1-8 data byte back
        tst     can_datalen     ; Check if all data was sent
        bne     crr_loop        ; If not, repeat sending
        rts


CAN_gnd         ; GetNextData
        lda     can_datalen     ; Check if all data was sent
        beq     cgnd_nodata
        cmp     #1
        beq     cgnd_checksum
        dec     can_datalen     ; Administrate one data byte processed
        lda     ,x
        jsr     addcs
        lda     ,x
        aix     #1              ; Point to next data
        rts
cgnd_nodata
        lda     #$FB            ; Filler Byte 
        rts
cgnd_checksum
        dec     can_datalen     ; Administrate one data byte processed
        lda     checksum 
        rts
        
CAN_SendData
        ; Send error answer
        bsr     CAN_SendPrep

        ; Message data
        bsr     CAN_gnd
        sta     CANTDSR0
        bsr     CAN_gnd
        sta     CANTDSR1
        bsr     CAN_gnd
        sta     CANTDSR2
        bsr     CAN_gnd
        sta     CANTDSR3
        bsr     CAN_gnd
        sta     CANTDSR4
        bsr     CAN_gnd
        sta     CANTDSR5
        bsr     CAN_gnd
        sta     CANTDSR6
        bsr     CAN_gnd
        sta     CANTDSR7

        ; CS EOR packetnumber to detect data packet order change 
        inc     packetnumber
        lda     checksum
        eor     packetnumber
        sta     checksum
        
        ; Set data length
        lda     #8
        sta     CANTDLR

        ; Transmit the message
        bsr     CAN_Send

        rts
        
can_readaddr
        clr     checksum
        lda     CANRDSR0        ; address hi
        sta     dump_addr
        jsr     addcs
        lda     CANRDSR1        ; address hi
        sta     dump_addr+1
        jsr     addcs
        rts

CAN_AckRx
        psha
        lda     #CAN_RXF_       ; Write 1 to clear the flag
        sta     CANRFLG
        pula
        tsta
        rts
        
; Answer subroutines
CAN_ansnull
        bsr     CAN_AckRx
        ; Send tester present answer
        bsr     CAN_SendPrep
        
        ; Message data not used
        ; Set data length
        clra
        sta     CANTDLR

        ; Transmit the message
        bsr     CAN_Send

        rts

CAN_ansok
        clra                    ; Error code is zero
CAN_anserr
        psha                    ; Save error code
        bsr     CAN_AckRx
        ; Send error answer
        bsr     CAN_SendPrep

        ; Message data is error code
        pula                    ; Restore error code
        sta     CANTDSR0

        ; Set data length
        lda     #1
        sta     CANTDLR

        ; Transmit the message
        bsr     CAN_Send
        rts

CAN_SendPrep
        pshhx
        ; Select first buffer
        lda     #1
        sta     CANTBSEL
        ; Set ID
        ldhx    #$1CDA
        sthx    can_idin
        lda     diag_sa
        sta     can_idin+2
        lda     ECUID
        sta     can_idin+3
        jsr     CAN_CalcID
        ldhx    can_idout
        sthx    CANTIDR0
        ldhx    can_idout+2
        sthx    CANTIDR2
        pulhx
        rts

CAN_Send
        ; Transmit the message
        lda     CANTBSEL
        sta     CANTFLG

        ; Wait while message is not transmitted
CANS_waittx        
        jsr     RTC_Handle
        lda     CANTFLG
        and     #CAN_TXE0_
        beq     CANS_waittx
        
        rts


cr_broadcast    ; Services in broadcast mode
        lda     CANRDLR         ; Check DLC (the command actually)
        and     #CANR_DLC3_|CANR_DLC2_|CANR_DLC1_|CANR_DLC0_
        cmp     #7              ; Check if Set ECU ID by serialnum
        beq     cr_bcsetid      ; BroadCast Set ID
        cmp     #1              ; Check if Instruction
        jne     c_errcodeuc     ; Command error
        lda     CANRDSR0        ; Check subservice
        cmp     #$22            ; Scan Network request
        jne     c_errcodeus     ; Only Scan Network request is suported

        bsr     CAN_AckRx       ; Ack Rx, from now on only the answer comes
        bsr     CAN_SendPrep

        mov     #6,wr_datac     ; Set length to copy
        clrhx                   ; Clear index
cr_scannet_loop
        lda     SERIAL_NUMBER,x ; Load number byte
        sta     CANTDSR0,x      ; Save into Tx meessage data buffer        
        aix     #1              ; Next index
        dbnz    wr_datac,cr_scannet_loop
        
        lda     ECUID
        sta     CANTDSR6
        lda     #7              ; Set data length
        sta     CANTDLR
        bsr     CAN_Send        ; Transmit the message
        rts

cr_bcsetid_nm   ; No Match        
        jsr     CAN_AckRx       ; Ack Rx, from now on only the answer comes
        rts
cr_bcsetid
        mov     #6,wr_datac     ; Set length to be sent
        clrhx                   ; Clear index
cr_bcsetid_loop
        lda     CANRDSR0,x
        cmp     SERIAL_NUMBER,x   ; Check serial number byte
        bne     cr_bcsetid_nm   ; Skip if not match (No answer needed)
        aix     #1
        dbnz    wr_datac,cr_bcsetid_loop
        
        lda     CANRDSR6	; Read new ECUID
        sta     wr_data         ; Save new ECUID into data buffer for write

        jsr     CAN_AckRx       ; Ack Rx, from now on only the answer comes

        lda     ECUID+1         ; Load original update counter
        inca                    ; increase by one
        sta     wr_data+1       ; Save back into buffer
        mov     #6,wr_datac     ; Set length of copy
        clrhx                   ; Clear index of copy
cbcsetid_cpy        
        lda     FINGERPR,x      ; Load fingerprint byte
        sta     wr_data+2,x     ; Save into buffer
        aix     #1
        dbnz    wr_datac,cbcsetid_cpy
        ldhx    #ECUID          ; Load address of ECUID
        sthx    dump_addr       ; Save as target address
        clr     wr_datat        ; Set length zero for erase first
        jsr     nvm_doit_fpok   ; Erase ECUID in EEPROM, no fingerprint needed
        bne     cbcsetid_reasp  ; In case of error, no more task
        ldhx    #ECUID          ; Load address of ECUID
        sthx    dump_addr       ; Save as target address
        mov     #8,wr_datat     ; Set length to 2 to Write
        jsr     nvm_doit_fpok   ; Write new ECUID, no fingerprint needed
cbcsetid_reasp
        jsr     CAN_anserr      ; Report error or success code 
        jsr     CAN_Init        ; Re-init CAN to update ID acceptance filter with new ECUID  
        rts

cr_wrfp
        clr     fp_cs           ; Clear checksum
        mov     #6,wr_datac     ; Set length to read fingerprint bytes
        clrhx                   ; Buffer to read bytes
cfngprnt_loop
        lda     CANRDSR0,x      ; Check service
        sta     wr_data,x       ; Save fingerprint byte
        add     fp_cs
        sta     fp_cs           ; Add received byte value to checksum 
        aix     #1
        dbnz    wr_datac,cfngprnt_loop
        lda     FINGERPR+6      ; Load original update counter
        inca                    ; increase by one
        sta     wr_data+6       ; Save back into buffer
        add     fp_cs
        sta     fp_cs           ; Add update counter value to checksum 
        lda     fp_cs           ; Load checksum of prevoius 7 bytes
        sta     wr_data+7       ; Save back into buffer

        ldhx    #FINGERPR       ; Load address of fingerprint
        sthx    dump_addr       ; Save as target address
        clr     wr_datat        ; Set length zero for erase first
        jsr     nvm_doit_fpok   ; Erase fingerprint in EEPROM, no fingerprint needed
        bne     cfngprnt_reasp  ; In case of error, no more task
        ldhx    #FINGERPR       ; Load address of fingerprint
        sthx    dump_addr       ; Save as target address
        mov     #8,wr_datat     ; Set length to 2 to Write
        jsr     nvm_doit_fpok   ; Write new fingerprint, no fingerprint needed
cfngprnt_reasp
        bne     cfngprnt_err    ; Jump if fingerprint write was not successful
        mov     #1,fpavail      ; Set flag if fingerprint is written well 
cfngprnt_err
        jsr     CAN_anserr      ; Report error or success code 
        rts



