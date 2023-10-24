; Example application with dzbl bootloader.
; This shows all services and interfaces of dzbl bootloader.


; Non-Volatile FLASH Options Register is handled by bootloader, not need to be handled here.


; BootLoader Configuration Register
BLCR            def     $FFAC           ; $FF (erased) is default settings
                ; bitnum BLCR_ET,0      ; Enable Terminal
                ; bitnum BLCR_ET,1      ; Enable Welcome string on SCI

        org     BLCR            ; BootLoader Configuration Register
        db      $FF             ; Enable both Terminal and Welcome SCI services

; EEPROM area
ECUID           def     $17F8   ; Own ID of ECU (Last page of EEPROM)
FINGERPR        def     $17F0   ; Fingerprint of bootloader usage (usually user info and timestamp) 

EECANBAUD       def     $17E8   ; CAN BaudRate settings in EEPROM
;        org     EECANBAUD
;        db      $FF,$FF         ; Default 500kbaud is used, but can be changed by EEPROM update by application
;        db      $00,$01         ; Baud = 4MHz / 1 / (1+2+1) = 1M.    Sample point = (1+2)/(1+2+1) = 75%
;        db      $00,$05         ; Baud = 4MHz / 1 / (1+6+1) = 500k.  Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 1M with fQuarz=8MHz)
;        db      $01,$05         ; Baud = 4MHz / 2 / (1+6+1) = 250k.  Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 500k with fQuarz=8MHz)
;        db      $03,$05         ; Baud = 4MHz / 4 / (1+6+1) = 125k.  Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 250k with fQuarz=8MHz)
;        db      $07,$05         ; Baud = 4MHz / 8 / (1+6+1) = 62.5k. Sample point = (1+6)/(1+6+1) = 87.5% (Baud = 125k with fQuarz=8MHz)

EESCIBAUD       def     $17E0   ; SCI BaudRate setting in EEPROM
;        org     EESCIBAUD
;        db      $FF             ; Default 57600 baud rate is used, but can be changed by EEPROM update by application
;        db      1               ; 1000k - 0%
;        db      2               ; 500k - 0%
;        db      4               ; 250k - 0%
;        db      5               ; 200k - 0%
;        db      9               ; 115200 - 3.68%
;        db      17              ; 57600 - 2.08%
;        db      26              ; 38400 - 0.16%
;        db      52              ; 19200 - 0.16%
;        db      104             ; 9600 - 0.16%

EEStartCnt      def     $17D8   ; Counter byte increased by one at each application software start

; Information in bootloader Flash
BL_VERSION      def     $FCF0   ; Bootloader version string with null termination
SERIAL_NUMBER   def     $FCF8   ; Hardware serial number (6 bytes + 0x55AA)

; Bootloader services. These are functions to be called by 'jsr' and will return.
        dw      KickCop         
KickCop         def     $EB00   ; Function to fresh watchdog without damage any register
MEM_doit        def     $EB04   ; Function to erase or write Flash or EEPROM

; RAM variables
RAMStartCnt     def     $0100   ; Teplorarily storage of EEStartCnt


; Application software entry point
        org     $4000
start
        sei                     ; Disable interrupts

        ; Stack init is done by bootloader. Not need to do here again.
        ; MCG_Init was done by bootloader. Not need to be done here again if fBus=16MHz is acceptable.
        ; PCB_Init was called by bootloader since its vector is stored at $FFA2. Not need to be called here again.
        bsr     SCI_Init        ; Init SCI. It is needed, because botloader leave SCI in uninicialized state.

        cli                     ; Enable interrupts

        ; Increase EEStartCnt in EEPROM by one
        ; - Save EEStartCnt+1 into RAM
        lda     EEStartCnt
        inca
        sta     RAMStartCnt
        ; - Erase Page
        ; Source address
        ais     #-2             ; reserve source address two bytes, here it is don't care
        ; Destination MEM address
        ldhx    #EEStartCnt
        pshx                    ; lo
        pshh                    ; hi
        ; Length of data
        clrx                    ; Null length will result erase operation
        pshx                    ; lo
        pshx                    ; hi
        jsr     MEM_doit        ; call
        ais     #6              ; release 6 byte parameters
        ; - Program 1 byte from RAM to EEPROM
        ; Source address
        ldhx    #RAMStartCnt
        pshx                    ; lo
        pshh                    ; hi
        ; Destination MEM address
        ldhx    #EEStartCnt
        pshx                    ; lo
        pshh                    ; hi
        ; Length of data
        ldhx    #$0001
        pshx                    ; lo
        pshh                    ; hi
        jsr     MEM_doit        ; call
        ais     #6              ; release 6 byte parameters

        jsr     SCI_welcome

loop
        ; Toggle LED
        lda     $0              ; PTA
        eor     #$40
        sta     $0              ; PTA

        ; Wait 65535*10 cycles
        ldhx    #$7FFF
wait
        jsr     KickCop         ; Fresh watchdog
        brset	5,$3C,scirxev   ; SCI1S1 no received byte

        lda     #10
wait2
        deca
        tsta
        bne     wait2

        aix     #-1
        cphx    #0
        bne     wait

        bra     loop
scirxev
        db      $AC             ; Illegal opcode to reset MCU

; Init SCI to receive serial data with baud rate 57600
SCI_Init
	clr	$3A             ; SCI1C1
        mov     #$0C,$3B        ; Set RE and TE in SCI1C2
	clr	$3E             ; SCI1C3
        clr     $38             ; SCI1BDH
        lda     EESCIBAUD       ; Load baud rate prescaler from EEPROM, same as bootloader uses
        sta     $39             ; Baud (16MHz / 16 / 17 = 57600) in SCI1BDL
        rts

; Prints a character from A.
SCI_putc
        jsr     KickCop         ; Fresh watchdog
	brclr	7,$3C,SCI_putc  ; not yet ready to transmit 
        sta     $3F             ; also SCTE is cleared here
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

PCB_Init
        ; Init LED port PTA6
        lda     #$40
        sta     $1              ; DDRA
        sta     $0              ; PTA
        rts
LED_On
        lda     $0              ; PTA
        ora     #$40
        sta     $0              ; PTA
        rts
LED_Off
        lda     $0              ; PTA
        and     #$BF
        sta     $0              ; PTA
        rts

hexakars
        db      '0123456789ABCDEF'

welcome fcs     $0A,"Example application for dzbl boorloader (github.com/butyi/dzbl) "
wstrid  fcs     $0A,"ID = "
strcnt  fcs     $0A,"New start counter = "
blver   fcs     $0A,"Bootloader version = "
ecuser  fcs     $0A,"ECU Serial number = "

SCI_welcome
        ldhx    #welcome
        jsr     SCI_puts

        ldhx    #wstrid
        jsr     SCI_puts
        lda     ECUID
        jsr     SCI_putb

        ldhx    #strcnt
        jsr     SCI_puts
        lda     EEStartCnt
        jsr     SCI_putb

        ldhx    #blver
        jsr     SCI_puts
        ldhx    #BL_VERSION
        jsr     SCI_puts

        ldhx    #ecuser
        jsr     SCI_puts
        ldhx    #SERIAL_NUMBER
sciw_loop
        lda     ,x
        jsr     SCI_putb
        aix     #1
        cphx    #SERIAL_NUMBER+8
        blo     sciw_loop

        lda     #$0A
        jsr     SCI_putc

        rts


; Vectors are stored
        org     $FFA2
        dw      PCB_Init
        org     $FFA4
        dw      LED_On
        org     $FFA6
        dw      LED_Off
        org     $FFFE           ; Place reset vector to its original place even though bootloader is used
        dw      start


