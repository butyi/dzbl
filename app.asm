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

        jsr     CAN_Init

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
        brset	5,$3C,scirxev   ; Framing error (break character)

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
        brset	1,$3C,resetecu  ; Framing error (break character) MCU reset needed to jump to bootloader
        lda     $3F             ; Read data register
        sta     $3F             ; Wrire data register, this is an echo actually
        jsr     CAN_SendA       ; Send character in a CAN message
        bra     loop
resetecu
        lda     $3F             ; Read data register to clear Framing error bit
        db      $AC             ; Illegal opcode to reset MCU to jump to bootloader

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


CAN_BASE        def     $1880
CANCTL0         equ     CAN_BASE+$00,1      ;MSCAN Control 0 Register
CANCTL1         equ     CAN_BASE+$01,1      ;MSCAN Control 1 Register
CANBTR0         equ     CAN_BASE+$02,1      ;MSCAN Bus Timing Register 0
CANBTR1         equ     CAN_BASE+$03,1      ;MSCAN Bus Timing Register 1
CANRFLG         equ     CAN_BASE+$04,1      ;MSCAN Receiver Flag Register
CANTBSEL        equ     CAN_BASE+$0A,1      ;MSCAN Transmit Buffer Selection
CANTIDR         equ     CAN_BASE+$30,1      ;MSCAN 0 Transmit Identifier Register 0
CANTDSR         equ     CAN_BASE+$34,1      ;MSCAN Transmit Data Segment Register 0
CANTDLR         equ     CAN_BASE+$3C,1      ;MSCAN Transmit Data Length Register
CANTFLG         equ     CAN_BASE+$06,1      ;MSCAN Transmitter Flag Register


CAN_Init
        ; MSCAN Enable, CLKSRC=1 use BusClk(16MHz), BORM=0 auto busoff recovery, SLPAK=0 no sleep
        lda     #$C0            ; CAN_CLKSRC 
        sta     CANCTL1

        ; Enter into Initialization Mode
        bsr     CAN_EnterInit

        ais     #-2             ; Reserve two bytes in stack for baud rate bytes 

        ; Use same baud rate like bootloader
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
        lda     #$01            ; Default 500kbaud value 
        sta     1,sp 
        lda     #$3A            ; Default 500kbaud value 
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

        ; Leave Initialization Mode
        bsr     CAN_ExitInit
        lda     #$FF

; Send message with A register
CAN_SendA
        psha        
        ; Select first buffer
        lda     #1
        sta     CANTBSEL

        ; Set ID
        lda     #$FF
        sta     CANTIDR+0
        sta     CANTIDR+1        ; Set IDE and SRR
        sta     CANTIDR+2
        and     #$FE            ; Clear RTR bit
        sta     CANTIDR+3
        
        ; Set message data
        pula
        sta     CANTDSR+0

        ; Set data length
        lda     #1
        sta     CANTDLR

        ; Transmit the message
        lda     CANTBSEL
        sta     CANTFLG

        rts

CAN_ExitInit
        ; Leave Initialization Mode
        lda     #$01
        coma
        and     CANCTL0
        sta     CANCTL0

        ; Wait for exit Initialization Mode Acknowledge
CAN_ChkExitInit
        lda     CANCTL1
        and     #$01
        bne     CAN_ChkExitInit
        
        rts

CAN_EnterInit
        ; Request init mode
        lda     CANCTL0
        ora     #$01
        sta     CANCTL0
CAN_ChkEnterInit
        ; Wait for Initialization Mode Acknowledge
        lda     CANCTL1
        and     #$01
        beq     CAN_ChkEnterInit
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


