; =============================================================================
; Flash, EEPROM, RAM write routines for MC9S08DZ family
; =============================================================================
; Module is basically designed to erase and write Flash and EEPROM.
;   RAM support is only added to be a common memory manipulation interface.   
; Due to FCDIV setting, allowed application bus frequency range is now 12 MHz - 9 MHz
;   If this range is not acceptable, FCDIV setting shall be modified in Bootloader,
;   and maybe appropriate MCG setup also need to be added to Bootloader  
; Mass erase
;   Not supported
; Sector erase abort
;   Not yet supported
; Sector erase
;   push sourceaddr=Don't care
;   push destinationaddr=address of page to be erased
;   push length=0
;   jsr MEM_doit
;   ais #6 to release parameters on stack 
; Byte program
;   push sourceaddr=address where the byte to be read from
;   push destinationaddr=address where the byte to be written to
;   push length=1
;   jsr MEM_doit
;   ais #6 to release parameters on stack 
; Burst program for n bytes (n = 2...768)
;   push sourceaddr=begining address where the bytes to be read from
;   push destinationaddr=begining address where the bytes to be written to
;   push length=n
;   jsr MEM_doit
;   ais #6 to release parameters on stack 
; Example 1: Erase Page 0x8000
;        ; Source address
;        ldhx    #doesntmatter
;        pshx                    ; lo
;        pshh                    ; hi
;        ; Destination MEM address
;        ldhx    #$8000
;        pshx                    ; lo
;        pshh                    ; hi
;        ; Length of data
;        ldhx    #$0000
;        pshx                    ; lo
;        pshh                    ; hi
;        jsr     MEM_doit        ; call
;        ais     #6              ; release 6 byte parameters
; Example 2: Burst Program 16 bytes from 0x8000 to 0x800F
;        ; Source address
;        ldhx    #bufferinram
;        pshx                    ; lo
;        pshh                    ; hi
;        ; Destination MEM address
;        ldhx    #$8000
;        pshx                    ; lo
;        pshh                    ; hi
;        ; Length of data
;        ldhx    #$0010
;        pshx                    ; lo
;        pshh                    ; hi
;        jsr     MEM_doit        ; call
;        ais     #6              ; release 6 byte parameters
; Do not access the manipulated MEM type during manupulation, even by this manipulator code! 
;  When MEM activity is executed from RAM, both Flash and EEPROM can be manipulated.
;  When only EEPROM to be manipulated, code can be executed from Flash.
;  If Flash need to be changed while there is lack of RAM, copy MEM_inFlash to EEPROM to execute.
; Do not cross boundaries of 768 bytes long pages!
; Do not write more data than 768 bytes!
; This uses RAM from 0x1000 to 0x107F for flash manipulator code

; ====================  EQUATES ===============================================
BUSCLK          equ     16000000 ; Bus clock in Hz


; ====================  VARIABLES  ========================================
#RAM
MEM_inRAM       equ     $1000
FCMDval         ds      1       ; Local variable for FCMD
sectnum         ds      1       ; Local variable for sector number
lpfn            ds      1       ; Last Page Fix Needed info: 
                                ; right after last (vector) page erase, reset vector and protection shall be written with proper value
 
#ROM

; ====================  PUBLIC FUNCTIONS  =========================================

RAM_write
        ; RAM and register write is much easier 
        ldhx    9,sp
        lda     ,x              ; Get byte from source address
        ldhx    7,sp
        sta     ,x              ; Write byte to destination address

        ; Decrement Length
        ldhx    5,sp
        aix     #-1
        sthx    5,sp
        beq     ramw_end        ; This was the last byte, no more queue, wait end of command
        
        ; Increment source address to select next byte
        ldhx    9,sp
        aix     #1
        sthx    9,sp

        ; Increment destination address to select next byte
        ldhx    7,sp
        aix     #1
        sthx    7,sp

        ; Queue the next byte as command
        bra     RAM_write
ramw_end
        clra                    ; return code: no error
        rts

; It calculates EEPROM sector number (return in A) from address in HX 
EESectCnt
        pshh
        pula                    ; address hi
        sub     #$14            ; Subtract EEPROM start address
        psha                    ; Save hi
        txa                     ; Lo into A
        pulx                    ; Hi into X
        lsrx                    ; /=2 : Shift right hi, LSB into carry
        rora                    ;       Shift right lo, carry into MSB
        lsrx                    ; /=2 : Shift right hi, LSB into carry
        rora                    ;       Shift right lo, carry into MSB
        lsrx                    ; /=2 : Shift right hi, LSB into carry
        rora                    ;       Shift right lo, carry into MSB
        ora     #$80            ; Add 0x80 to not be overlap with Flash sector numbers
        rts                     ; Here A is 0x00...0x7F, the EEPROM sector number
; Last sector (0x17F8-0x17FF) is reserved for ECU own ID and timestamp of its last change


; It calculates Flash sector number (return in A) from address high byte in A 
;  $01=>00 $04=>01 $07=>02 $0A=>03 $0D=>04 (RAM, does not exists as Flash)
;  $10=>05 (XROM: $1080-$12FF reserved for application identification)
;  $13=>06 (XROM: $1300-$13FF reserved for bootloader and hardware identification)
;  $16=>07 (EEPROM and High Page Registers)
;  $19=>08 $1C=>09 $1F=>10 $22=>11 (Application)
;  $25=>12 $28=>13 $2B=>14 $2E=>15
;  $31=>16 $34=>17 $37=>18 $3A=>19
;  $3D=>20 $40=>21 $43=>22 $46=>23
;  $49=>24 $4C=>25 $4F=>26 $52=>27
;  $55=>28 $58=>29 $5B=>30 $5E=>31
;  $61=>32 $64=>33 $67=>34 $6A=>35
;  $6D=>36 $70=>37 $73=>38 $76=>39
;  $79=>40 $7C=>41 $7F=>42 $82=>43
;  $85=>44 $88=>45 $8B=>46 $8E=>47
;  $91=>48 $94=>49 $97=>50 $9A=>51
;  $9D=>52 $A0=>53 $A3=>54 $A6=>55
;  $A9=>56 $AC=>57 $AF=>58 $B2=>59
;  $B5=>60 $B8=>61 $BB=>62 $BE=>63
;  $C1=>64 $C4=>65 $C7=>66 $CA=>67
;  $CD=>68 $D0=>69 $D3=>70 $D6=>71
;  $D9=>72 $DC=>73 $DF=>74 $E2=>75
;  $E5=>76 $E8=>77 (Application last page)
;  $EB=>78 $EE=>79 $F1=>80 $F4=>81 $F7=>82 $FA=>83 (Bootloader code $EB00-$FCFF 6*3k=18k)
;  $FD=>84 (Vector and NVR: open for application, only reset vector shall always point to bootloader start)
FlashSectCnt
        deca
        clrh
        ldx     #3
        div
        rts
        
; MEM_DoIt function
; Common function for write into all supported memory types
; parameters are on stack
; 1,sp: return address hi
; 2,sp: return address lo
; 3,sp: length hi
; 4,sp: length lo
; 5,sp: destination address hi
; 6,sp: destination address lo
; 7,sp: source address hi
; 8,sp: source address lo
; Return code in A:
;   - 0x00=Success
;   - 0x10=Access error
;   - 0x20=Protection violation
;   - 0x50=Length is zero
;   - 0x60=Length is too high
;   - 0xA0=Address error (Bootloader code range is prohibited to be changed) 
;   - 0xB0=Page boundary violation 
memd_eeprom     ; Be informed, this is not start of MEM_DoIt function
        ; Check length EEPROM(8)
        ldhx    3,sp            ; length
        jeq     memd_nbovi      ; Skip boundary check if Erase is requested by zero length
        cphx    #8              ; EEPROM sector size
        bls     memd_eelenok
        lda     #$60            ; If larger, length error code
        rts                     ; to be returned
memd_eelenok
        ; Check sector boundary
        ldhx    5,sp            ; destination address
        bsr     EESectCnt
        sta     sectnum         ; Here is sector number of start address
        lda     6,sp            ; destination address lo
        add     4,sp            ; length lo, just to set carry
        tax
        lda     5,sp            ; destination address hi
        adc     3,sp            ; add length hi with carry
        psha
        pulh
        aix     #-1
        bsr     EESectCnt       ; Here is sector number of end address
        cmp     sectnum         ; Compare with sector number of start address
        jeq     memd_nbovi      ; If same, no sector boundary violation happened
        lda     #$B0            ; If different, boundary violation error code
        rts                     ; to be returned
memd_ramreg     ; RAM and register write
        ; Check length RAM(0x300)
        ldhx    3,sp            ; length
        cphx    #$300           ; RAM max size (same as Flash, same buffer is used)
        bls     memd_rlenok
        lda     #60             ; If larger, length error code
        rts                     ; to be returned
memd_rlenok
        ; Check if length is not zero
        ldhx    3,sp            ; length
        bne     memd_lennozero  ; Non zero length, go further 
        lda     #$50            ; Zero length, return error code
        rts
memd_lennozero
        jsr     RAM_write       ; Call RAM write       
        rts
MEM_doit
        clr     lpfn            ; Most of time last page fix not needed
        ; Check addresses
        lda     5,sp            ; destination address hi
        cmp     #$18            ; This is high page registers
        beq     memd_ramreg     ; what is RAM actually               
        cmp     #$14            ; This is EEPROM
        beq     memd_eeprom     ; EEPROM has different page size                
        cmp     #$15            ; This is EEPROM
        beq     memd_eeprom     ; EEPROM has different page size                
        cmp     #$16            ; This is EEPROM
        beq     memd_eeprom     ; EEPROM has different page size                
        cmp     #$17            ; This is EEPROM
        beq     memd_eeprom     ; EEPROM has different page size                
        cmp     #$10            ; Direct page registers and RAM
        blo     memd_ramreg     ; This is RAM
        bhi     memd_flash      ; $10< are Flash 
        tst     6,sp            ; destination address lo
        bpl     memd_ramreg     ; If hi is $10 and lo is plus ($00-$7F), it is still RAM
memd_flash
        bsr     FlashSectCnt
        sta     sectnum         ; Here is sector number of start address
        cmp     #79
        blo     memd_nboot
        cmp     #83
        bhi     memd_nboot
        lda     #$A0            ; Bootloader area, return error code
        rts
memd_nboot      ; Not boorloader area wanted to be touched
        cmp     #84
        bne     memd_nblpage    ; jump if not the last page
        bset    1,lpfn          ; Save info if last page write is triggered
        lda     4,sp
        ora     3,sp            ; length check (zero or not)
        bne     memd_nblpage    ; jump if not erase called
        bset    0,lpfn          ; Save info if last page erase is called, fix needed
        bclr    1,lpfn          ; Last page but not write
memd_nblpage    ; Not the last page wanted to be touched
        lda     4,sp
        ora     3,sp            ; length check (zero or not)
        beq     memd_nbovi      ; Skip boundary check if erase called by zero length
        lda     6,sp            ; destination address lo
        add     4,sp            ; length lo, set carry
        tax
        lda     5,sp            ; destination address hi
        adc     3,sp            ; add length hi with carry
        psha
        pulh
        aix     #-1
        pshh
        pula
        jsr     FlashSectCnt    ; Here is sector number of end address
        cmp     sectnum         ; Compare with sector number of start address
        beq     memd_nbovi      ; If same, no sector boundary violation happened
        lda     #$B0            ; If different, boundary violation error code
        rts                     ; to be returned
memd_nbovi      ; No BOundary VIolation
        ; Check length Flash(0x300)
        ldhx    3,sp            ; length
        cphx    #$300           ; Flash sector size
        bls     memd_flenok
        lda     #$60            ; If larger, length error code
        rts                     ; to be returned
memd_flenok
        ; Identify command code for the desired command according to Length (0=Erase,1=byte,otherwise=burst)
        lda     3,sp            ; Length hi
        ora     4,sp            ; Length lo
        bne     memd_noe        ; NOt Erase
        lda     #PageErase_     ; Length==0 -> Sector Erase
        sta     FCMDval
        inc     4,sp            ; Length lo to be 1 insted of 0 to prevent overflow of later decrementation
        bra     memd_cmdok
memd_noe
        lda     3,sp            ; Length hi
        bne     memd_noby       ; NOt BYte
        lda     4,sp            ; Length lo
        cmp     #1
        bne     memd_noby       ; NOt BYte
        lda     #ByteProg_      ; Length==1 -> Byte Program
        sta     FCMDval
        bra     memd_cmdok
memd_noby
        lda     #BurstProg_     ; Length>1 -> Burst Program
        sta     FCMDval
memd_cmdok

        ; Disable interrupts to be sure no MEM access happen during MEM activity 
        sei

        ; Do the MEM activity in RAM
        jsr     MEM_inRAM
        
        brclr   0,lpfn,memd_nlpf
        ; Fix last page after erase

        ; Write bootloader start into reset vector
        ldhx    #2
        sthx    3,sp            ; length
        ldhx    #Vreset
        sthx    5,sp            ; destination address
        ldhx    #entry
        sthx    wr_data
        ldhx    #wr_data        ; Source buffer shall be in RAM
        sthx    7,sp            ; source address
        lda     #BurstProg_     ; Burst Program
        sta     FCMDval
        jsr     MEM_inRAM
        
        ; Release Flash and EEPROM protection (NVPROT=$FF, NVOPT=$E2 (unsecured))        
        ldhx    #3
        sthx    3,sp            ; length
        ldhx    #NVPROT
        sthx    5,sp            ; destination address
        lda     #$FF            ; Release all Flash and EEPROM
        sta     wr_data
        sta     wr_data+1
        lda     #NVOPT_VALUE    ; Unsecure, EE8byte, enable backdoor, disable vector redirection
        sta     wr_data+2
        ldhx    #wr_data        ; Source buffer shall be in RAM
        sthx    7,sp            ; source address
        lda     #BurstProg_     ; Burst Program
        sta     FCMDval
        jsr     MEM_inRAM
        

memd_nlpf    ; No Last Page Fix
        
        ; Enable interrupts
        cli
        
        rts


; ===================== ROUTINE TO BE EXECUTED IN RAM ===========================================
; Stack pointers of parameters below are +2 as written for MEM_doit because call address of MEM_inFlash
MEM_inFlash
        ; FACCERR and FPVIOL must be cleared by writing a 1 to them in FSTAT
        lda     #FACCERR_|FPVIOL_
        sta     FSTAT
mif_loop
        ; Wait while FCBEF is zero
        lda     FSTAT
        bit     #FCBEF_
        beq     mif_loop

        ; Write data value to address in the Flash or EEPROM array to select the sector
        ldhx    9,sp
        lda     ,x              ; Get byte from source address
        ldhx    7,sp            ; If destination address
        brclr   1,lpfn,mem_noresetvect ; jump if no last page 
        cphx    #$FFFE          ; is not reset vector ($FFFE or $FFFF)
        blo     mem_noresetvect ; Keep destination address
        aix     #-94            ; If reset vector, modify destination address to $FFA0  
mem_noresetvect
        sta     ,x              ; Write byte to destination address

        ; Write the command code for the desired command according to length (0=Erase,1=byte,otherwise=burst)
        lda     FCMDval         ; already identified command code
        sta     FCMD

        ; Write a 1 to the FCBEF bit in FSTAT to clear FCBEF and launch the command
        lda     #FCBEF_
        sta     FSTAT

        ; Wait 4 cycles
        lda     11,sp
        
        ; Check if any error happend meantime
        lda     FSTAT
        bit     #FACCERR_|FPVIOL_
        bne     mem_err

        ; If not the last byte (burst program), do not wait, but queue the next byte
        ; Decrement Length
        ldhx    5,sp            ; Length
        aix     #-1
        sthx    5,sp
        beq     mem_wait        ; This was the last byte, no more queue, wait end of command

        ; Increment source address to select next byte
        ldhx    9,sp            ; Source address
        aix     #1
        sthx    9,sp
        
        ; Increment destination address to select next byte
        ldhx    7,sp            ; Destination address
        aix     #1
        sthx    7,sp

        ; Queue the next byte as command
        bra     mif_loop
mem_wait
        ; Wait until the FCCF bit in FSTAT is set
        lda     FSTAT
        bit     #FCCF_
        beq     mem_wait
        ; Success
        clra
mem_err ; Error
        rts
        
MEM_inFlashend  equ     *
MEM_len         equ     MEM_inFlashend-MEM_inFlash+1 
; ===================== END OF ROUTINE TO BE EXECUTED IN RAM ===========================================


; Initialization of Non Volatime Memory manipulations
MEM_Init
        ; FACCERR and FPVIOL must be cleared by writing a 1 to them in FSTAT
        lda     #FACCERR_|FPVIOL_
        sta     FSTAT

        ; Set FCDIV to be fFCLK between 150 kHz and 200 kHz (16Mhz/(79+1)=200kHz)
        lda     #BUSCLK/200000-1
        sta     FCDIV
        
        ; Copy MEM_inFlash function to MEM_inRAM
        clrh
        ldx     #MEM_len
memi_loop
        lda     MEM_inFlash-1,x
        sta     MEM_inRAM-1,x
        dbnzx   memi_loop

        rts




