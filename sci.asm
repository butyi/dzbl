; =============================================================================
; Serial Communication interface
; =============================================================================

;-----------------------------------------
; EEPROM config
;-----------------------------------------
sci_config      ; Config in EEPROM
        org     EESCIBAUD       ; Values with fBus=16MHz -> fSCI=1MHz
;        db      1               ; 1000k - 0%
;        db      2               ; 500k - 0%
;        db      4               ; 250k - 0%
;        db      5               ; 200k - 0%
;        db      9               ; 115200 - 3.68%
        db      17              ; 57600 - 2.08%
;        db      26              ; 38400 - 0.16%
;        db      52              ; 19200 - 0.16%
;        db      104             ; 9600 - 0.16%
        org     sci_config

;-----------------------------------------
; STRINGS
;-----------------------------------------
hexakars
        db      '0123456789ABCDEF'


;-----------------------------------------
; FUNCTIONS
;-----------------------------------------
; Initialize SCI controller
; ------------------------------------------------------------------------------
; Serial Communications Interface (S08SCIV4)
; Init SCI to receive serial data with baud rate 57600
SCI_Init
	clr	SCI1C1	
        mov     #TE_|RE_,SCI1C2
	clr	SCI1C3	
        clr     SCI1BDH
        lda     EESCIBAUD       ; Read baud rate from EEPROM
        cmp     #$FF
        bne     si_baudvalid
        lda     #17             ; Use default 57600 if value is invalid ($FF)
si_baudvalid
        sta     SCI1BDL
        rts

SCI_Deinit
	clr	SCI1C1
        clr     SCI1BDH	
        mov     #$04,SCI1BDL	
	clr	SCI1C2
	clr	SCI1S2
	clr	SCI1C3
	clr	SCI1D
        rts

; Prints a byte in hexa format from A.
SCI_putb
        pshh                    ; Save registers
        pshx
        psha
        nsa                     ; First upper 4 bits
        and     #$F
        tax
        clrh
        lda     hexakars,x
        bsr     SCI_putc
        lda     1,sp            ; Next lower 4 bits
        and     #$F
        tax
        clrh
        lda     hexakars,x
        bsr     SCI_putc
        pula                    ; Restore registers
        pulx
        pulh
        rts

; Prints a byte in hexa format from A and a new line character.
SCI_putbn
        bsr     SCI_putb
        bsr     SCI_putn
        rts
        
; Prints HX in hexa format and a new line character.
SCI_puthxn
        pshx
        pshh
        pula
        bsr     SCI_putb
        pula
        bsr     SCI_putbn
        rts
SCI_putn
        psha
        lda     #$0A
        bsr     SCI_putc
        pula
        rts
        

; Tries to read character from SCI. Carry bit shows if there is received character in A or not.
SCI_getc
	brclr	RDRF.,SCI1S1,gc_nothing ; no received byte
        lda     SCI1D
        sec                     ; RX info in carry bit
        rts
gc_nothing
        clc
        rts

; Prints a string. String address is in H:X.
SCI_puts
        lda     ,x
        beq     scips_v
        bsr     SCI_putc
        aix     #1
        bra     SCI_puts
scips_v
        rts


; Prints a character from A.
SCI_putc
        bsr     RTC_Handle
	brclr	TDRE.,SCI1S1,SCI_putc     ; not yet ready to transmit 
        sta     SCI1D           ; also SCTE is cleared here
        rts


